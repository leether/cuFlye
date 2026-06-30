// SPDX-License-Identifier: BSD-3-Clause

#include <cuda_runtime_api.h>

#include "cuflye_cuda_raii.hpp"

#include <chrono>
#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace
{
static const uint32_t MAX_KMER_SIZE = 32;

struct QueryReadMeta
{
	int64_t queryId;
	uint64_t sequenceOffset;
	uint32_t length;
	char padding[4];
};

struct IndexWindow
{
	int64_t targetId;
	uint64_t targetPos;
	char targetStrand;
	char sequence[MAX_KMER_SIZE + 1];
	char padding[7];
};

struct RepetitiveWindow
{
	char sequence[MAX_KMER_SIZE + 1];
};

struct CandidateRecord
{
	int64_t queryId;
	uint64_t queryPos;
	uint64_t kmer;
	int64_t targetId;
	uint64_t targetPos;
	char targetStrand;
	char padding[7];
};

struct Options
{
	std::string readsTsv;
	std::string indexTsv;
	std::string repetitiveTsv;
	std::string outputTsv;
	std::string cpuOutputTsv;
	std::string jsonOutput;
	uint32_t kmerSize = 0;
	int device = 0;
	bool hasMemoryBudget = false;
	unsigned long long memoryBudgetBytes = 0;
};

struct QueryReadSet
{
	std::vector<QueryReadMeta> reads;
	std::vector<char> bases;
	size_t maxReadLength = 0;
};

using Clock = std::chrono::steady_clock;

struct TimingSummary
{
	double inputParseMs = 0.0;
	double cpuOracleMs = 0.0;
	double cudaSetupMs = 0.0;
	double deviceAllocationMs = 0.0;
	double hostToDeviceMs = 0.0;
	double kernelMs = 0.0;
	double markKernelMs = 0.0;
	double flagDeviceToHostMs = 0.0;
	double hostPrefixSumMs = 0.0;
	double offsetsHostToDeviceMs = 0.0;
	double emitKernelMs = 0.0;
	double hostOutputAllocationMs = 0.0;
	double sparseOutputAllocationMs = 0.0;
	double outputDeviceToHostMs = 0.0;
	double deviceToHostMs = 0.0;
	double compactMs = 0.0;
	double writeOutputMs = 0.0;
	double totalBeforeJsonMs = 0.0;
};

__host__ __device__ uint64_t dnaBaseToBits(char base)
{
	switch (base)
	{
	case 'A':
	case 'a':
		return 0;
	case 'C':
	case 'c':
		return 1;
	case 'G':
	case 'g':
		return 2;
	case 'T':
	case 't':
		return 3;
	default:
		return 0;
	}
}

__host__ __device__ uint64_t encodeKmerAt(const char* sequence,
										  uint64_t start,
										  uint32_t kmerSize)
{
	uint64_t representation = 0;
	for (uint32_t index = 0; index < kmerSize; ++index)
	{
		representation <<= 2;
		representation += dnaBaseToBits(sequence[start + index]);
	}
	return representation;
}

__host__ __device__ uint64_t reverseComplement(uint64_t representation, uint32_t kmerSize)
{
	uint64_t reverse = 0;
	for (uint32_t index = 0; index < kmerSize; ++index)
	{
		reverse <<= 2;
		reverse += ~representation & 3ULL;
		representation >>= 2;
	}
	return reverse;
}

__host__ __device__ uint64_t standardForm(uint64_t representation, uint32_t kmerSize)
{
	uint64_t revComp = reverseComplement(representation, kmerSize);
	return revComp < representation ? revComp : representation;
}

__device__ bool isRepetitiveLookupKmer(uint64_t lookupKmer,
									   const RepetitiveWindow* repetitiveKmers,
									   size_t repetitiveCount,
									   uint32_t kmerSize)
{
	for (size_t index = 0; index < repetitiveCount; ++index)
	{
		uint64_t repetitive = standardForm(encodeKmerAt(repetitiveKmers[index].sequence, 0, kmerSize),
										   kmerSize);
		if (repetitive == lookupKmer) return true;
	}
	return false;
}

__device__ size_t findReadIndex(size_t windowIndex,
								const uint64_t* readWindowOffsets,
								size_t readCount)
{
	for (size_t readIndex = 0; readIndex < readCount; ++readIndex)
	{
		if (windowIndex < readWindowOffsets[readIndex + 1]) return readIndex;
	}
	return readCount - 1;
}

__device__ bool buildCandidateRecord(size_t pairIndex,
									 const QueryReadMeta* reads,
									 size_t readCount,
									 const char* readBases,
									 const uint64_t* readWindowOffsets,
									 const IndexWindow* indexEntries,
									 size_t indexCount,
									 const RepetitiveWindow* repetitiveKmers,
									 size_t repetitiveCount,
									 uint32_t kmerSize,
									 CandidateRecord* output)
{
	size_t queryWindowIndex = pairIndex / indexCount;
	size_t targetIndex = pairIndex % indexCount;
	size_t readIndex = findReadIndex(queryWindowIndex, readWindowOffsets, readCount);
	uint64_t queryPos = static_cast<uint64_t>(queryWindowIndex - readWindowOffsets[readIndex]);

	const QueryReadMeta* query = &reads[readIndex];
	const char* querySequence = readBases + query->sequenceOffset;
	const IndexWindow* target = &indexEntries[targetIndex];
	uint64_t queryKmer = encodeKmerAt(querySequence, queryPos, kmerSize);
	uint64_t queryLookupKmer = standardForm(queryKmer, kmerSize);

	if (isRepetitiveLookupKmer(queryLookupKmer, repetitiveKmers, repetitiveCount, kmerSize))
	{
		return false;
	}

	uint64_t targetLookupKmer = standardForm(encodeKmerAt(target->sequence, 0, kmerSize),
											 kmerSize);
	if (queryLookupKmer != targetLookupKmer)
	{
		return false;
	}

	if (query->queryId == target->targetId && queryPos == target->targetPos)
	{
		return false;
	}

	if (output)
	{
		CandidateRecord record;
		record.queryId = query->queryId;
		record.queryPos = queryPos;
		record.kmer = queryKmer;
		record.targetId = target->targetId;
		record.targetPos = target->targetPos;
		record.targetStrand = target->targetStrand;
		for (char& ch : record.padding) ch = 0;
		*output = record;
	}
	return true;
}

__global__ void markCandidateRecordsKernel(const QueryReadMeta* reads,
										   size_t readCount,
										   const char* readBases,
										   const uint64_t* readWindowOffsets,
										   const IndexWindow* indexEntries,
										   size_t indexCount,
										   const RepetitiveWindow* repetitiveKmers,
										   size_t repetitiveCount,
										   uint32_t kmerSize,
										   uint8_t* validFlags,
										   size_t pairCount)
{
	size_t pairIndex = static_cast<size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
	if (pairIndex >= pairCount) return;
	validFlags[pairIndex] = buildCandidateRecord(pairIndex, reads, readCount, readBases,
												 readWindowOffsets, indexEntries,
												 indexCount, repetitiveKmers,
												 repetitiveCount, kmerSize, nullptr) ? 1 : 0;
}

__global__ void emitCandidateRecordsKernel(const QueryReadMeta* reads,
										   size_t readCount,
										   const char* readBases,
										   const uint64_t* readWindowOffsets,
										   const IndexWindow* indexEntries,
										   size_t indexCount,
										   const RepetitiveWindow* repetitiveKmers,
										   size_t repetitiveCount,
										   uint32_t kmerSize,
										   const uint8_t* validFlags,
										   const uint32_t* outputOffsets,
										   CandidateRecord* output,
										   size_t pairCount)
{
	size_t pairIndex = static_cast<size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
	if (pairIndex >= pairCount || !validFlags[pairIndex]) return;

	CandidateRecord record;
	if (!buildCandidateRecord(pairIndex, reads, readCount, readBases,
							  readWindowOffsets, indexEntries, indexCount,
							  repetitiveKmers, repetitiveCount, kmerSize, &record))
	{
		return;
	}
	output[outputOffsets[pairIndex]] = record;
}

[[noreturn]] void usageError(const std::string& message)
{
	throw std::runtime_error(message +
		"\nUsage: cuflye-cuda-read-window-smoke --kmer-size N --reads-tsv PATH "
		"--index-tsv PATH --output-tsv PATH [--repetitive-kmers-tsv PATH] "
		"[--cpu-output-tsv PATH] [--device N] [--memory-budget-bytes N] "
		"[--json-output PATH]");
}

unsigned long long parseUnsigned(const std::string& value, const std::string& name)
{
	if (value.empty()) usageError(name + " must not be empty");
	if (value[0] == '-') usageError(name + " must be unsigned: " + value);
	char* end = nullptr;
	errno = 0;
	unsigned long long parsed = std::strtoull(value.c_str(), &end, 10);
	if (errno != 0 || end == value.c_str() || *end != '\0')
	{
		usageError(name + " must be an unsigned decimal integer: " + value);
	}
	return parsed;
}

int parseInt(const std::string& value, const std::string& name)
{
	unsigned long long parsed = parseUnsigned(value, name);
	if (parsed > static_cast<unsigned long long>(std::numeric_limits<int>::max()))
	{
		usageError(name + " is outside int range: " + value);
	}
	return static_cast<int>(parsed);
}

uint32_t parseKmerSize(const std::string& value, const std::string& name)
{
	unsigned long long parsed = parseUnsigned(value, name);
	if (parsed == 0 || parsed > MAX_KMER_SIZE)
	{
		usageError(name + " must be in range 1..32");
	}
	return static_cast<uint32_t>(parsed);
}

Options parseArgs(int argc, char** argv)
{
	Options options;
	const char* envDevice = std::getenv("CUFLYE_CUDA_DEVICE");
	if (envDevice && envDevice[0]) options.device = parseInt(envDevice, "CUFLYE_CUDA_DEVICE");
	const char* envBudget = std::getenv("CUFLYE_CUDA_MEMORY_BUDGET_BYTES");
	if (envBudget && envBudget[0])
	{
		options.hasMemoryBudget = true;
		options.memoryBudgetBytes = parseUnsigned(envBudget, "CUFLYE_CUDA_MEMORY_BUDGET_BYTES");
	}

	for (int index = 1; index < argc; ++index)
	{
		std::string arg = argv[index];
		auto requireValue = [&](const std::string& name) -> std::string
		{
			if (index + 1 >= argc) usageError(name + " requires a value");
			return argv[++index];
		};

		if (arg == "--kmer-size")
		{
			options.kmerSize = parseKmerSize(requireValue(arg), arg);
		}
		else if (arg == "--reads-tsv")
		{
			options.readsTsv = requireValue(arg);
		}
		else if (arg == "--index-tsv")
		{
			options.indexTsv = requireValue(arg);
		}
		else if (arg == "--repetitive-kmers-tsv")
		{
			options.repetitiveTsv = requireValue(arg);
		}
		else if (arg == "--output-tsv")
		{
			options.outputTsv = requireValue(arg);
		}
		else if (arg == "--cpu-output-tsv")
		{
			options.cpuOutputTsv = requireValue(arg);
		}
		else if (arg == "--device")
		{
			options.device = parseInt(requireValue(arg), arg);
		}
		else if (arg == "--memory-budget-bytes")
		{
			options.hasMemoryBudget = true;
			options.memoryBudgetBytes = parseUnsigned(requireValue(arg), arg);
		}
		else if (arg == "--json-output")
		{
			options.jsonOutput = requireValue(arg);
		}
		else if (arg == "-h" || arg == "--help")
		{
			std::cout
				<< "Usage: cuflye-cuda-read-window-smoke --kmer-size N "
				<< "--reads-tsv PATH --index-tsv PATH --output-tsv PATH "
				<< "[--repetitive-kmers-tsv PATH] [--cpu-output-tsv PATH] "
				<< "[--device N] [--memory-budget-bytes N] [--json-output PATH]\n";
			std::exit(0);
		}
		else
		{
			usageError("Unknown option: " + arg);
		}
	}

	if (options.kmerSize == 0) usageError("--kmer-size is required");
	if (options.readsTsv.empty()) usageError("--reads-tsv is required");
	if (options.indexTsv.empty()) usageError("--index-tsv is required");
	if (options.outputTsv.empty()) usageError("--output-tsv is required");
	return options;
}

void checkCuda(cudaError_t status, const std::string& action)
{
	if (status != cudaSuccess)
	{
		throw std::runtime_error(action + ": code=" +
								 std::to_string(static_cast<int>(status)) +
								 " name=" + cudaGetErrorName(status) +
								 " text=" + cudaGetErrorString(status));
	}
}

double elapsedMs(Clock::time_point start, Clock::time_point stop)
{
	return std::chrono::duration<double, std::milli>(stop - start).count();
}

double cudaEventElapsedMs(const cuflye::cuda_raii::CudaEvent& start,
						  const cuflye::cuda_raii::CudaEvent& stop,
						  const std::string& action)
{
	float milliseconds = 0.0f;
	checkCuda(cudaEventElapsedTime(&milliseconds, start.get(), stop.get()), action);
	return milliseconds;
}

int64_t parseInt64Field(const std::string& value, const std::string& fieldName)
{
	if (value.empty()) throw std::runtime_error(fieldName + " must not be empty");
	char* end = nullptr;
	errno = 0;
	long long parsed = std::strtoll(value.c_str(), &end, 10);
	if (errno != 0 || end == value.c_str() || *end != '\0')
	{
		throw std::runtime_error(fieldName + " must be a signed decimal integer: " + value);
	}
	return static_cast<int64_t>(parsed);
}

uint64_t parseUint64Field(const std::string& value, const std::string& fieldName)
{
	return parseUnsigned(value, fieldName);
}

std::vector<std::string> splitTabs(const std::string& line)
{
	std::vector<std::string> fields;
	size_t begin = 0;
	while (true)
	{
		size_t end = line.find('\t', begin);
		if (end == std::string::npos)
		{
			fields.push_back(line.substr(begin));
			break;
		}
		fields.push_back(line.substr(begin, end - begin));
		begin = end + 1;
	}
	return fields;
}

std::vector<std::string> parseLineFields(std::string line,
										 size_t lineNumber,
										 const std::string& path,
										 size_t expectedFields)
{
	if (!line.empty() && line.back() == '\r') line.pop_back();
	if (line.empty())
	{
		throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
								 ": blank records are not allowed");
	}
	std::vector<std::string> fields = splitTabs(line);
	if (fields.size() != expectedFields)
	{
		throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
								 ": expected " + std::to_string(expectedFields) +
								 " tab-separated fields");
	}
	return fields;
}

void validateDnaSequence(const std::string& sequence,
						 size_t minSize,
						 size_t maxSize,
						 const std::string& path,
						 size_t lineNumber)
{
	if (sequence.size() < minSize || sequence.size() > maxSize)
	{
		throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
								 ": sequence length is outside accepted range");
	}
	for (char base : sequence)
	{
		if (base != 'A' && base != 'a' && base != 'C' && base != 'c' &&
			base != 'G' && base != 'g' && base != 'T' && base != 't')
		{
			throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
									 ": sequence must contain only A/C/G/T");
		}
	}
}

void appendReadBases(std::vector<char>& bases, const std::string& sequence)
{
	bases.insert(bases.end(), sequence.begin(), sequence.end());
}

void copySequence(char* destination, size_t capacity, const std::string& sequence)
{
	std::memset(destination, 0, capacity);
	std::memcpy(destination, sequence.data(), sequence.size());
}

QueryReadSet readReads(const std::string& path, uint32_t kmerSize)
{
	std::ifstream input(path);
	if (!input) throw std::runtime_error("Can't open read TSV: " + path);

	QueryReadSet readSet;
	std::string line;
	size_t lineNumber = 0;
	while (std::getline(input, line))
	{
		++lineNumber;
		std::vector<std::string> fields = parseLineFields(line, lineNumber, path, 2);
		validateDnaSequence(fields[1], kmerSize, std::numeric_limits<size_t>::max(),
							path, lineNumber);
		if (fields[1].size() > std::numeric_limits<uint32_t>::max())
		{
			throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
									 ": read length exceeds uint32 range");
		}
		QueryReadMeta read;
		std::memset(&read, 0, sizeof(read));
		read.queryId = parseInt64Field(fields[0], "query_id");
		read.sequenceOffset = static_cast<uint64_t>(readSet.bases.size());
		read.length = static_cast<uint32_t>(fields[1].size());
		appendReadBases(readSet.bases, fields[1]);
		if (fields[1].size() > readSet.maxReadLength) readSet.maxReadLength = fields[1].size();
		readSet.reads.push_back(read);
	}
	if (readSet.reads.empty()) throw std::runtime_error("read TSV is empty: " + path);
	if (readSet.bases.empty()) throw std::runtime_error("read TSV has no bases: " + path);
	return readSet;
}

std::vector<IndexWindow> readIndex(const std::string& path, uint32_t kmerSize)
{
	std::ifstream input(path);
	if (!input) throw std::runtime_error("Can't open index TSV: " + path);

	std::vector<IndexWindow> entries;
	std::string line;
	size_t lineNumber = 0;
	while (std::getline(input, line))
	{
		++lineNumber;
		std::vector<std::string> fields = parseLineFields(line, lineNumber, path, 4);
		if (fields[2] != "+" && fields[2] != "-")
		{
			throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
									 ": target_strand must be '+' or '-'");
		}
		validateDnaSequence(fields[3], kmerSize, kmerSize, path, lineNumber);
		IndexWindow entry;
		std::memset(&entry, 0, sizeof(entry));
		entry.targetId = parseInt64Field(fields[0], "target_id");
		entry.targetPos = parseUint64Field(fields[1], "target_pos");
		entry.targetStrand = fields[2][0];
		copySequence(entry.sequence, MAX_KMER_SIZE + 1, fields[3]);
		entries.push_back(entry);
	}
	if (entries.empty()) throw std::runtime_error("index TSV is empty: " + path);
	return entries;
}

std::vector<RepetitiveWindow> readRepetitiveKmers(const std::string& path, uint32_t kmerSize)
{
	std::vector<RepetitiveWindow> repetitive;
	if (path.empty()) return repetitive;

	std::ifstream input(path);
	if (!input) throw std::runtime_error("Can't open repetitive k-mer TSV: " + path);

	std::string line;
	size_t lineNumber = 0;
	while (std::getline(input, line))
	{
		++lineNumber;
		std::vector<std::string> fields = parseLineFields(line, lineNumber, path, 1);
		validateDnaSequence(fields[0], kmerSize, kmerSize, path, lineNumber);
		RepetitiveWindow repetitiveKmer;
		std::memset(&repetitiveKmer, 0, sizeof(repetitiveKmer));
		copySequence(repetitiveKmer.sequence, MAX_KMER_SIZE + 1, fields[0]);
		repetitive.push_back(repetitiveKmer);
	}
	return repetitive;
}

std::vector<uint64_t> buildReadWindowOffsets(const std::vector<QueryReadMeta>& reads,
											 uint32_t kmerSize)
{
	std::vector<uint64_t> offsets;
	offsets.reserve(reads.size() + 1);
	offsets.push_back(0);
	for (const QueryReadMeta& read : reads)
	{
		if (read.length < kmerSize) throw std::runtime_error("read shorter than k-mer size");
		uint64_t windows = static_cast<uint64_t>(read.length - kmerSize + 1);
		offsets.push_back(offsets.back() + windows);
	}
	return offsets;
}

bool hostIsRepetitive(uint64_t lookupKmer,
					  const std::vector<RepetitiveWindow>& repetitiveKmers,
					  uint32_t kmerSize)
{
	for (const RepetitiveWindow& repetitive : repetitiveKmers)
	{
		uint64_t repetitiveLookup = standardForm(encodeKmerAt(repetitive.sequence, 0, kmerSize),
												 kmerSize);
		if (repetitiveLookup == lookupKmer) return true;
	}
	return false;
}

std::vector<CandidateRecord> generateCpuOracle(const QueryReadSet& readSet,
											   const std::vector<uint64_t>& readWindowOffsets,
											   const std::vector<IndexWindow>& indexEntries,
											   const std::vector<RepetitiveWindow>& repetitiveKmers,
											   uint32_t kmerSize)
{
	std::vector<CandidateRecord> records;
	for (size_t readIndex = 0; readIndex < readSet.reads.size(); ++readIndex)
	{
		const QueryReadMeta& query = readSet.reads[readIndex];
		const char* querySequence = readSet.bases.data() + query.sequenceOffset;
		for (uint64_t queryPos = 0; queryPos < readWindowOffsets[readIndex + 1] - readWindowOffsets[readIndex]; ++queryPos)
		{
			uint64_t queryKmer = encodeKmerAt(querySequence, queryPos, kmerSize);
			uint64_t queryLookupKmer = standardForm(queryKmer, kmerSize);
			if (hostIsRepetitive(queryLookupKmer, repetitiveKmers, kmerSize)) continue;
			for (const IndexWindow& target : indexEntries)
			{
				uint64_t targetLookupKmer = standardForm(encodeKmerAt(target.sequence, 0, kmerSize),
														 kmerSize);
				if (queryLookupKmer != targetLookupKmer) continue;
				if (query.queryId == target.targetId && queryPos == target.targetPos) continue;

				CandidateRecord record;
				std::memset(&record, 0, sizeof(record));
				record.queryId = query.queryId;
				record.queryPos = queryPos;
				record.kmer = queryKmer;
				record.targetId = target.targetId;
				record.targetPos = target.targetPos;
				record.targetStrand = target.targetStrand;
				records.push_back(record);
			}
		}
	}
	return records;
}

void writeCandidateTsv(const std::string& path, const std::vector<CandidateRecord>& records)
{
	if (path.empty()) return;
	std::ofstream output(path);
	if (!output)
	{
		throw std::runtime_error("Can't open candidate TSV output: " + path);
	}

	for (const CandidateRecord& record : records)
	{
		output << record.queryId << '\t'
			   << record.queryPos << '\t'
			   << record.kmer << '\t'
			   << record.targetId << '\t'
			   << record.targetPos << '\t'
			   << record.targetStrand << '\n';
	}
}

std::string jsonEscape(const std::string& text)
{
	std::ostringstream out;
	for (char ch : text)
	{
		switch (ch)
		{
		case '\\': out << "\\\\"; break;
		case '"': out << "\\\""; break;
		case '\n': out << "\\n"; break;
		case '\r': out << "\\r"; break;
		case '\t': out << "\\t"; break;
		default: out << ch;
		}
	}
	return out.str();
}

std::string buildJson(const Options& options,
					  const cudaDeviceProp& prop,
					  size_t freeBytes,
					  size_t totalBytes,
					  size_t requiredBytes,
					  size_t readCount,
					  size_t queryWindows,
					  size_t readBaseBytes,
					  size_t maxReadLength,
					  size_t indexCount,
					  size_t repetitiveCount,
					  size_t pairCount,
					  size_t outputCount,
					  bool cpuOracleEnabled,
					  const TimingSummary& timing)
{
	std::ostringstream json;
	json << std::fixed << std::setprecision(3);
	json << "{\n";
	json << "  \"adapter\": \"cuda-read-window-smoke-v0\",\n";
	json << "  \"status\": \"ok\",\n";
	json << "  \"abi\": \"candidate-record-v1\",\n";
	json << "  \"device\": " << options.device << ",\n";
	json << "  \"device_name\": \"" << jsonEscape(prop.name) << "\",\n";
	json << "  \"compute_capability\": \"" << prop.major << "." << prop.minor << "\",\n";
	json << "  \"kmer_size\": " << options.kmerSize << ",\n";
	json << "  \"reads\": " << readCount << ",\n";
	json << "  \"query_windows\": " << queryWindows << ",\n";
	json << "  \"read_base_bytes\": " << readBaseBytes << ",\n";
	json << "  \"max_read_length\": " << maxReadLength << ",\n";
	json << "  \"index_entries\": " << indexCount << ",\n";
	json << "  \"repetitive_kmers\": " << repetitiveCount << ",\n";
	json << "  \"pair_count\": " << pairCount << ",\n";
	json << "  \"records\": " << outputCount << ",\n";
	json << "  \"read_record_size_bytes\": " << sizeof(QueryReadMeta) << ",\n";
	json << "  \"read_meta_record_size_bytes\": " << sizeof(QueryReadMeta) << ",\n";
	json << "  \"index_record_size_bytes\": " << sizeof(IndexWindow) << ",\n";
	json << "  \"candidate_record_size_bytes\": " << sizeof(CandidateRecord) << ",\n";
	json << "  \"device_allocation_bytes\": " << requiredBytes << ",\n";
	json << "  \"memory_free_bytes\": " << static_cast<unsigned long long>(freeBytes) << ",\n";
	json << "  \"memory_total_bytes\": " << static_cast<unsigned long long>(totalBytes) << ",\n";
	json << "  \"memory_budget_bytes\": ";
	if (options.hasMemoryBudget) json << options.memoryBudgetBytes;
	else json << "null";
	json << ",\n";
	json << "  \"memory_budget_satisfied\": true,\n";
	json << "  \"dynamic_read_bases\": true,\n";
	json << "  \"output_strategy\": \"sparse-offsets-v1\",\n";
	json << "  \"dense_pair_output_materialized\": false,\n";
	json << "  \"device_side_read_windowing\": true,\n";
	json << "  \"device_side_kmer_encoding\": true,\n";
	json << "  \"device_side_standard_form\": true,\n";
	json << "  \"cpu_oracle_enabled\": " << (cpuOracleEnabled ? "true" : "false") << ",\n";
	json << "  \"timing_ms\": {\n";
	json << "    \"input_parse\": " << timing.inputParseMs << ",\n";
	json << "    \"cpu_oracle\": " << timing.cpuOracleMs << ",\n";
	json << "    \"cuda_setup\": " << timing.cudaSetupMs << ",\n";
	json << "    \"device_allocation\": " << timing.deviceAllocationMs << ",\n";
	json << "    \"host_to_device\": " << timing.hostToDeviceMs << ",\n";
	json << "    \"kernel\": " << timing.kernelMs << ",\n";
	json << "    \"mark_kernel\": " << timing.markKernelMs << ",\n";
	json << "    \"flag_device_to_host\": " << timing.flagDeviceToHostMs << ",\n";
	json << "    \"host_prefix_sum\": " << timing.hostPrefixSumMs << ",\n";
	json << "    \"offsets_host_to_device\": " << timing.offsetsHostToDeviceMs << ",\n";
	json << "    \"emit_kernel\": " << timing.emitKernelMs << ",\n";
	json << "    \"host_output_allocation\": " << timing.hostOutputAllocationMs << ",\n";
	json << "    \"sparse_output_allocation\": " << timing.sparseOutputAllocationMs << ",\n";
	json << "    \"output_device_to_host\": " << timing.outputDeviceToHostMs << ",\n";
	json << "    \"device_to_host\": " << timing.deviceToHostMs << ",\n";
	json << "    \"compact\": " << timing.compactMs << ",\n";
	json << "    \"write_output\": " << timing.writeOutputMs << ",\n";
	json << "    \"total_before_json\": " << timing.totalBeforeJsonMs << "\n";
	json << "  },\n";
	json << "  \"reads_tsv\": \"" << jsonEscape(options.readsTsv) << "\",\n";
	json << "  \"index_tsv\": \"" << jsonEscape(options.indexTsv) << "\",\n";
	json << "  \"repetitive_kmers_tsv\": \"" << jsonEscape(options.repetitiveTsv) << "\",\n";
	json << "  \"cpu_output_tsv\": \"" << jsonEscape(options.cpuOutputTsv) << "\",\n";
	json << "  \"output_tsv\": \"" << jsonEscape(options.outputTsv) << "\"\n";
	json << "}\n";
	return json.str();
}

void writeText(const std::string& path, const std::string& text)
{
	if (path.empty()) return;
	std::ofstream output(path);
	if (!output)
	{
		throw std::runtime_error("Can't open output file: " + path);
	}
	output << text;
}

size_t checkedMultiply(size_t left, size_t right, const std::string& name)
{
	if (right != 0 && left > std::numeric_limits<size_t>::max() / right)
	{
		throw std::runtime_error(name + " size overflow");
	}
	return left * right;
}

size_t checkedAdd(size_t left, size_t right, const std::string& name)
{
	if (left > std::numeric_limits<size_t>::max() - right)
	{
		throw std::runtime_error(name + " size overflow");
	}
	return left + right;
}
}

int main(int argc, char** argv)
{
	try
	{
		auto totalStart = Clock::now();
		TimingSummary timing;
		Options options = parseArgs(argc, argv);

		auto inputStart = Clock::now();
		QueryReadSet readSet = readReads(options.readsTsv, options.kmerSize);
		std::vector<uint64_t> readWindowOffsets = buildReadWindowOffsets(readSet.reads, options.kmerSize);
		std::vector<IndexWindow> indexEntries = readIndex(options.indexTsv, options.kmerSize);
		std::vector<RepetitiveWindow> repetitiveKmers =
			readRepetitiveKmers(options.repetitiveTsv, options.kmerSize);

		size_t queryWindows = static_cast<size_t>(readWindowOffsets.back());
		size_t pairCount = checkedMultiply(queryWindows, indexEntries.size(), "query/index pair");
		if (pairCount == 0) throw std::runtime_error("query/index pair count is zero");
		timing.inputParseMs = elapsedMs(inputStart, Clock::now());

		if (!options.cpuOutputTsv.empty())
		{
			auto cpuStart = Clock::now();
			std::vector<CandidateRecord> cpuRecords =
				generateCpuOracle(readSet, readWindowOffsets, indexEntries, repetitiveKmers, options.kmerSize);
			if (cpuRecords.empty()) throw std::runtime_error("CPU oracle emitted no candidate records");
			writeCandidateTsv(options.cpuOutputTsv, cpuRecords);
			timing.cpuOracleMs = elapsedMs(cpuStart, Clock::now());
		}

		auto cudaSetupStart = Clock::now();
		checkCuda(cudaSetDevice(options.device), "cudaSetDevice failed");
		cudaDeviceProp prop;
		std::memset(&prop, 0, sizeof(prop));
		checkCuda(cudaGetDeviceProperties(&prop, options.device), "cudaGetDeviceProperties failed");

		size_t freeBytes = 0;
		size_t totalBytes = 0;
		checkCuda(cudaMemGetInfo(&freeBytes, &totalBytes), "cudaMemGetInfo failed");
		timing.cudaSetupMs = elapsedMs(cudaSetupStart, Clock::now());

		size_t readBytes = checkedMultiply(readSet.reads.size(), sizeof(QueryReadMeta), "read metadata buffer");
		size_t readBaseBytes = checkedMultiply(readSet.bases.size(), sizeof(char), "read base buffer");
		size_t offsetBytes = checkedMultiply(readWindowOffsets.size(), sizeof(uint64_t), "read window offset buffer");
		size_t indexBytes = checkedMultiply(indexEntries.size(), sizeof(IndexWindow), "index buffer");
		size_t repetitiveBytes = checkedMultiply(repetitiveKmers.size(), sizeof(RepetitiveWindow),
												 "repetitive k-mer buffer");
		size_t flagBytes = checkedMultiply(pairCount, sizeof(uint8_t), "valid flag buffer");
		size_t outputOffsetBytes = checkedMultiply(pairCount, sizeof(uint32_t), "output offset buffer");
		size_t requiredBytes = checkedAdd(readBytes, offsetBytes, "device allocation");
		requiredBytes = checkedAdd(requiredBytes, readBaseBytes, "device allocation");
		requiredBytes = checkedAdd(requiredBytes, indexBytes, "device allocation");
		requiredBytes = checkedAdd(requiredBytes, repetitiveBytes, "device allocation");
		requiredBytes = checkedAdd(requiredBytes, flagBytes, "device allocation");
		requiredBytes = checkedAdd(requiredBytes, outputOffsetBytes, "device allocation");

		if (options.hasMemoryBudget && requiredBytes > options.memoryBudgetBytes)
		{
			throw std::runtime_error("CUDA read window smoke memory budget is smaller than required device allocation");
		}
		if (requiredBytes > freeBytes)
		{
			throw std::runtime_error("CUDA read window smoke required device allocation exceeds free device memory");
		}

		auto allocationStart = Clock::now();
		cuflye::cuda_raii::DeviceBuffer<QueryReadMeta> deviceReads(readBytes, "read metadata");
		cuflye::cuda_raii::DeviceBuffer<char> deviceReadBases(readBaseBytes, "read bases");
		cuflye::cuda_raii::DeviceBuffer<uint64_t> deviceReadWindowOffsets(offsetBytes,
																		  "read offsets");
		cuflye::cuda_raii::DeviceBuffer<IndexWindow> deviceIndex(indexBytes, "index");
		cuflye::cuda_raii::DeviceBuffer<RepetitiveWindow> deviceRepetitive(repetitiveBytes,
																		   "repetitive k-mers");
		cuflye::cuda_raii::DeviceBuffer<uint8_t> deviceFlags(flagBytes, "flags");
		cuflye::cuda_raii::DeviceBuffer<uint32_t> deviceOutputOffsets(outputOffsetBytes,
																	   "output offsets");
		timing.deviceAllocationMs = elapsedMs(allocationStart, Clock::now());

		cuflye::cuda_raii::CudaEvent h2dStart("host to device start");
		cuflye::cuda_raii::CudaEvent h2dStop("host to device stop");
		checkCuda(cudaEventRecord(h2dStart.get()), "cudaEventRecord H2D start failed");
		checkCuda(cudaMemcpy(deviceReads.get(), readSet.reads.data(), readBytes, cudaMemcpyHostToDevice),
				  "cudaMemcpy reads host-to-device failed");
		checkCuda(cudaMemcpy(deviceReadBases.get(), readSet.bases.data(), readBaseBytes,
							 cudaMemcpyHostToDevice),
				  "cudaMemcpy read bases host-to-device failed");
		checkCuda(cudaMemcpy(deviceReadWindowOffsets.get(), readWindowOffsets.data(), offsetBytes,
							 cudaMemcpyHostToDevice),
				  "cudaMemcpy read offsets host-to-device failed");
		checkCuda(cudaMemcpy(deviceIndex.get(), indexEntries.data(), indexBytes, cudaMemcpyHostToDevice),
				  "cudaMemcpy index host-to-device failed");
		if (repetitiveBytes)
		{
			checkCuda(cudaMemcpy(deviceRepetitive.get(), repetitiveKmers.data(), repetitiveBytes,
								 cudaMemcpyHostToDevice),
					  "cudaMemcpy repetitive k-mers host-to-device failed");
		}
		checkCuda(cudaMemset(deviceFlags.get(), 0, flagBytes), "cudaMemset flags failed");
		checkCuda(cudaEventRecord(h2dStop.get()), "cudaEventRecord H2D stop failed");
		checkCuda(cudaEventSynchronize(h2dStop.get()), "cudaEventSynchronize H2D stop failed");
		timing.hostToDeviceMs = cudaEventElapsedMs(h2dStart, h2dStop,
												  "cudaEventElapsedTime H2D failed");

		const int threadsPerBlock = 128;
		const int blocks = static_cast<int>((pairCount + threadsPerBlock - 1) / threadsPerBlock);
		cuflye::cuda_raii::CudaEvent markStart("mark kernel start");
		cuflye::cuda_raii::CudaEvent markStop("mark kernel stop");
		checkCuda(cudaEventRecord(markStart.get()), "cudaEventRecord mark start failed");
		markCandidateRecordsKernel<<<blocks, threadsPerBlock>>>(
			deviceReads.get(),
			readSet.reads.size(),
			deviceReadBases.get(),
			deviceReadWindowOffsets.get(),
			deviceIndex.get(),
			indexEntries.size(),
			deviceRepetitive.get(),
			repetitiveKmers.size(),
			options.kmerSize,
			deviceFlags.get(),
			pairCount);
		checkCuda(cudaGetLastError(), "markCandidateRecordsKernel launch failed");
		checkCuda(cudaEventRecord(markStop.get()), "cudaEventRecord mark stop failed");
		checkCuda(cudaEventSynchronize(markStop.get()), "markCandidateRecordsKernel execution failed");
		timing.markKernelMs = cudaEventElapsedMs(markStart, markStop,
												"cudaEventElapsedTime mark failed");

		auto hostFlagAllocationStart = Clock::now();
		std::vector<uint8_t> validFlags(pairCount);
		timing.hostOutputAllocationMs = elapsedMs(hostFlagAllocationStart, Clock::now());

		cuflye::cuda_raii::CudaEvent flagD2hStart("flag device to host start");
		cuflye::cuda_raii::CudaEvent flagD2hStop("flag device to host stop");
		checkCuda(cudaEventRecord(flagD2hStart.get()), "cudaEventRecord flag D2H start failed");
		checkCuda(cudaMemcpy(validFlags.data(), deviceFlags.get(), flagBytes, cudaMemcpyDeviceToHost),
				  "cudaMemcpy flags device-to-host failed");
		checkCuda(cudaEventRecord(flagD2hStop.get()), "cudaEventRecord flag D2H stop failed");
		checkCuda(cudaEventSynchronize(flagD2hStop.get()), "cudaEventSynchronize flag D2H stop failed");
		timing.flagDeviceToHostMs = cudaEventElapsedMs(flagD2hStart, flagD2hStop,
													  "cudaEventElapsedTime flag D2H failed");

		auto prefixStart = Clock::now();
		std::vector<uint32_t> outputOffsets(pairCount);
		uint32_t outputCount = 0;
		for (size_t index = 0; index < validFlags.size(); ++index)
		{
			outputOffsets[index] = outputCount;
			if (validFlags[index])
			{
				if (outputCount == std::numeric_limits<uint32_t>::max())
				{
					throw std::runtime_error("candidate output count exceeds uint32 range");
				}
				++outputCount;
			}
		}
		if (outputCount == 0) throw std::runtime_error("GPU emitted no candidate records");
		timing.hostPrefixSumMs = elapsedMs(prefixStart, Clock::now());
		timing.compactMs = timing.hostPrefixSumMs;

		cuflye::cuda_raii::CudaEvent offsetsH2dStart("offsets host to device start");
		cuflye::cuda_raii::CudaEvent offsetsH2dStop("offsets host to device stop");
		checkCuda(cudaEventRecord(offsetsH2dStart.get()), "cudaEventRecord offsets H2D start failed");
		checkCuda(cudaMemcpy(deviceOutputOffsets.get(), outputOffsets.data(), outputOffsetBytes,
							 cudaMemcpyHostToDevice),
				  "cudaMemcpy output offsets host-to-device failed");
		checkCuda(cudaEventRecord(offsetsH2dStop.get()), "cudaEventRecord offsets H2D stop failed");
		checkCuda(cudaEventSynchronize(offsetsH2dStop.get()), "cudaEventSynchronize offsets H2D stop failed");
		timing.offsetsHostToDeviceMs = cudaEventElapsedMs(offsetsH2dStart, offsetsH2dStop,
														 "cudaEventElapsedTime offsets H2D failed");

		size_t outputBytes = checkedMultiply(static_cast<size_t>(outputCount),
											 sizeof(CandidateRecord),
											 "compact output buffer");
		requiredBytes = checkedAdd(requiredBytes, outputBytes, "device allocation");
		if (options.hasMemoryBudget && requiredBytes > options.memoryBudgetBytes)
		{
			throw std::runtime_error("CUDA read window smoke compact output exceeds memory budget");
		}
		if (requiredBytes > freeBytes)
		{
			throw std::runtime_error("CUDA read window smoke compact output exceeds free device memory");
		}

		auto sparseOutputAllocationStart = Clock::now();
		cuflye::cuda_raii::DeviceBuffer<CandidateRecord> deviceOutput(outputBytes,
																	  "compact output");
		timing.sparseOutputAllocationMs = elapsedMs(sparseOutputAllocationStart, Clock::now());

		cuflye::cuda_raii::CudaEvent emitStart("emit kernel start");
		cuflye::cuda_raii::CudaEvent emitStop("emit kernel stop");
		checkCuda(cudaEventRecord(emitStart.get()), "cudaEventRecord emit start failed");
		emitCandidateRecordsKernel<<<blocks, threadsPerBlock>>>(
			deviceReads.get(),
			readSet.reads.size(),
			deviceReadBases.get(),
			deviceReadWindowOffsets.get(),
			deviceIndex.get(),
			indexEntries.size(),
			deviceRepetitive.get(),
			repetitiveKmers.size(),
			options.kmerSize,
			deviceFlags.get(),
			deviceOutputOffsets.get(),
			deviceOutput.get(),
			pairCount);
		checkCuda(cudaGetLastError(), "emitCandidateRecordsKernel launch failed");
		checkCuda(cudaEventRecord(emitStop.get()), "cudaEventRecord emit stop failed");
		checkCuda(cudaEventSynchronize(emitStop.get()), "emitCandidateRecordsKernel execution failed");
		timing.emitKernelMs = cudaEventElapsedMs(emitStart, emitStop,
												"cudaEventElapsedTime emit failed");
		timing.kernelMs = timing.markKernelMs + timing.emitKernelMs;

		auto hostOutputAllocationStart = Clock::now();
		std::vector<CandidateRecord> gpuRecords(outputCount);
		timing.hostOutputAllocationMs += elapsedMs(hostOutputAllocationStart, Clock::now());

		cuflye::cuda_raii::CudaEvent outputD2hStart("output device to host start");
		cuflye::cuda_raii::CudaEvent outputD2hStop("output device to host stop");
		checkCuda(cudaEventRecord(outputD2hStart.get()), "cudaEventRecord output D2H start failed");
		checkCuda(cudaMemcpy(gpuRecords.data(), deviceOutput.get(), outputBytes, cudaMemcpyDeviceToHost),
				  "cudaMemcpy compact output device-to-host failed");
		checkCuda(cudaEventRecord(outputD2hStop.get()), "cudaEventRecord output D2H stop failed");
		checkCuda(cudaEventSynchronize(outputD2hStop.get()), "cudaEventSynchronize output D2H stop failed");
		timing.outputDeviceToHostMs = cudaEventElapsedMs(outputD2hStart, outputD2hStop,
														"cudaEventElapsedTime output D2H failed");
		timing.deviceToHostMs = timing.flagDeviceToHostMs + timing.outputDeviceToHostMs;

		auto writeStart = Clock::now();
		writeCandidateTsv(options.outputTsv, gpuRecords);
		timing.writeOutputMs = elapsedMs(writeStart, Clock::now());
		timing.totalBeforeJsonMs = elapsedMs(totalStart, Clock::now());

		std::string json = buildJson(options, prop, freeBytes, totalBytes, requiredBytes,
									 readSet.reads.size(), queryWindows, readBaseBytes,
									 readSet.maxReadLength, indexEntries.size(),
									 repetitiveKmers.size(), pairCount, gpuRecords.size(),
									 !options.cpuOutputTsv.empty(), timing);
		writeText(options.jsonOutput, json);
		std::cout << json;
		return 0;
	}
	catch (const std::exception& exc)
	{
		std::cerr << "cuFlye CUDA read window smoke failed: " << exc.what() << "\n";
		return 1;
	}
}
