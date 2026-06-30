// SPDX-License-Identifier: BSD-3-Clause

#include <cuda_runtime_api.h>

#include "cuflye_cuda_raii.hpp"

#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace
{
static const uint32_t MAX_KMER_SIZE = 32;
static const uint32_t MAX_READ_SIZE = 256;

struct QueryRead
{
	int64_t queryId;
	uint32_t length;
	char sequence[MAX_READ_SIZE + 1];
	char padding[3];
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
										  uint32_t start,
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

__global__ void generateCandidateRecordsKernel(const QueryRead* reads,
											   size_t readCount,
											   const uint64_t* readWindowOffsets,
											   const IndexWindow* indexEntries,
											   size_t indexCount,
											   const RepetitiveWindow* repetitiveKmers,
											   size_t repetitiveCount,
											   uint32_t kmerSize,
											   CandidateRecord* output,
											   uint8_t* validFlags,
											   size_t pairCount)
{
	size_t pairIndex = static_cast<size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
	if (pairIndex >= pairCount) return;

	size_t queryWindowIndex = pairIndex / indexCount;
	size_t targetIndex = pairIndex % indexCount;
	size_t readIndex = findReadIndex(queryWindowIndex, readWindowOffsets, readCount);
	uint32_t queryPos = static_cast<uint32_t>(queryWindowIndex - readWindowOffsets[readIndex]);

	const QueryRead* query = &reads[readIndex];
	const IndexWindow* target = &indexEntries[targetIndex];
	uint64_t queryKmer = encodeKmerAt(query->sequence, queryPos, kmerSize);
	uint64_t queryLookupKmer = standardForm(queryKmer, kmerSize);

	if (isRepetitiveLookupKmer(queryLookupKmer, repetitiveKmers, repetitiveCount, kmerSize))
	{
		validFlags[pairIndex] = 0;
		return;
	}

	uint64_t targetLookupKmer = standardForm(encodeKmerAt(target->sequence, 0, kmerSize),
											 kmerSize);
	if (queryLookupKmer != targetLookupKmer)
	{
		validFlags[pairIndex] = 0;
		return;
	}

	if (query->queryId == target->targetId && queryPos == target->targetPos)
	{
		validFlags[pairIndex] = 0;
		return;
	}

	CandidateRecord record;
	record.queryId = query->queryId;
	record.queryPos = queryPos;
	record.kmer = queryKmer;
	record.targetId = target->targetId;
	record.targetPos = target->targetPos;
	record.targetStrand = target->targetStrand;
	for (char& ch : record.padding) ch = 0;
	output[pairIndex] = record;
	validFlags[pairIndex] = 1;
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
						 uint32_t minSize,
						 uint32_t maxSize,
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

void copySequence(char* destination, size_t capacity, const std::string& sequence)
{
	std::memset(destination, 0, capacity);
	std::memcpy(destination, sequence.data(), sequence.size());
}

std::vector<QueryRead> readReads(const std::string& path, uint32_t kmerSize)
{
	std::ifstream input(path);
	if (!input) throw std::runtime_error("Can't open read TSV: " + path);

	std::vector<QueryRead> reads;
	std::string line;
	size_t lineNumber = 0;
	while (std::getline(input, line))
	{
		++lineNumber;
		std::vector<std::string> fields = parseLineFields(line, lineNumber, path, 2);
		validateDnaSequence(fields[1], kmerSize, MAX_READ_SIZE, path, lineNumber);
		QueryRead read;
		std::memset(&read, 0, sizeof(read));
		read.queryId = parseInt64Field(fields[0], "query_id");
		read.length = static_cast<uint32_t>(fields[1].size());
		copySequence(read.sequence, MAX_READ_SIZE + 1, fields[1]);
		reads.push_back(read);
	}
	if (reads.empty()) throw std::runtime_error("read TSV is empty: " + path);
	return reads;
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

std::vector<uint64_t> buildReadWindowOffsets(const std::vector<QueryRead>& reads,
											 uint32_t kmerSize)
{
	std::vector<uint64_t> offsets;
	offsets.reserve(reads.size() + 1);
	offsets.push_back(0);
	for (const QueryRead& read : reads)
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

std::vector<CandidateRecord> generateCpuOracle(const std::vector<QueryRead>& reads,
											   const std::vector<uint64_t>& readWindowOffsets,
											   const std::vector<IndexWindow>& indexEntries,
											   const std::vector<RepetitiveWindow>& repetitiveKmers,
											   uint32_t kmerSize)
{
	std::vector<CandidateRecord> records;
	for (size_t readIndex = 0; readIndex < reads.size(); ++readIndex)
	{
		const QueryRead& query = reads[readIndex];
		for (uint64_t queryPos = 0; queryPos < readWindowOffsets[readIndex + 1] - readWindowOffsets[readIndex]; ++queryPos)
		{
			uint64_t queryKmer = encodeKmerAt(query.sequence, static_cast<uint32_t>(queryPos), kmerSize);
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

std::vector<CandidateRecord> compactGpuRecords(const std::vector<CandidateRecord>& records,
											   const std::vector<uint8_t>& validFlags)
{
	std::vector<CandidateRecord> compacted;
	for (size_t index = 0; index < records.size(); ++index)
	{
		if (validFlags[index]) compacted.push_back(records[index]);
	}
	return compacted;
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
					  size_t indexCount,
					  size_t repetitiveCount,
					  size_t pairCount,
					  size_t outputCount)
{
	std::ostringstream json;
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
	json << "  \"index_entries\": " << indexCount << ",\n";
	json << "  \"repetitive_kmers\": " << repetitiveCount << ",\n";
	json << "  \"pair_count\": " << pairCount << ",\n";
	json << "  \"records\": " << outputCount << ",\n";
	json << "  \"read_record_size_bytes\": " << sizeof(QueryRead) << ",\n";
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
	json << "  \"device_side_read_windowing\": true,\n";
	json << "  \"device_side_kmer_encoding\": true,\n";
	json << "  \"device_side_standard_form\": true,\n";
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
		Options options = parseArgs(argc, argv);
		std::vector<QueryRead> reads = readReads(options.readsTsv, options.kmerSize);
		std::vector<uint64_t> readWindowOffsets = buildReadWindowOffsets(reads, options.kmerSize);
		std::vector<IndexWindow> indexEntries = readIndex(options.indexTsv, options.kmerSize);
		std::vector<RepetitiveWindow> repetitiveKmers =
			readRepetitiveKmers(options.repetitiveTsv, options.kmerSize);

		size_t queryWindows = static_cast<size_t>(readWindowOffsets.back());
		size_t pairCount = checkedMultiply(queryWindows, indexEntries.size(), "query/index pair");
		if (pairCount == 0) throw std::runtime_error("query/index pair count is zero");

		std::vector<CandidateRecord> cpuRecords =
			generateCpuOracle(reads, readWindowOffsets, indexEntries, repetitiveKmers, options.kmerSize);
		if (cpuRecords.empty()) throw std::runtime_error("CPU oracle emitted no candidate records");
		writeCandidateTsv(options.cpuOutputTsv, cpuRecords);

		checkCuda(cudaSetDevice(options.device), "cudaSetDevice failed");
		cudaDeviceProp prop;
		std::memset(&prop, 0, sizeof(prop));
		checkCuda(cudaGetDeviceProperties(&prop, options.device), "cudaGetDeviceProperties failed");

		size_t freeBytes = 0;
		size_t totalBytes = 0;
		checkCuda(cudaMemGetInfo(&freeBytes, &totalBytes), "cudaMemGetInfo failed");

		size_t readBytes = checkedMultiply(reads.size(), sizeof(QueryRead), "read buffer");
		size_t offsetBytes = checkedMultiply(readWindowOffsets.size(), sizeof(uint64_t), "read window offset buffer");
		size_t indexBytes = checkedMultiply(indexEntries.size(), sizeof(IndexWindow), "index buffer");
		size_t repetitiveBytes = checkedMultiply(repetitiveKmers.size(), sizeof(RepetitiveWindow),
												 "repetitive k-mer buffer");
		size_t outputBytes = checkedMultiply(pairCount, sizeof(CandidateRecord), "output buffer");
		size_t flagBytes = checkedMultiply(pairCount, sizeof(uint8_t), "valid flag buffer");
		size_t requiredBytes = checkedAdd(readBytes, offsetBytes, "device allocation");
		requiredBytes = checkedAdd(requiredBytes, indexBytes, "device allocation");
		requiredBytes = checkedAdd(requiredBytes, repetitiveBytes, "device allocation");
		requiredBytes = checkedAdd(requiredBytes, outputBytes, "device allocation");
		requiredBytes = checkedAdd(requiredBytes, flagBytes, "device allocation");

		if (options.hasMemoryBudget && requiredBytes > options.memoryBudgetBytes)
		{
			throw std::runtime_error("CUDA read window smoke memory budget is smaller than required device allocation");
		}
		if (requiredBytes > freeBytes)
		{
			throw std::runtime_error("CUDA read window smoke required device allocation exceeds free device memory");
		}

		cuflye::cuda_raii::DeviceBuffer<QueryRead> deviceReads(readBytes, "reads");
		cuflye::cuda_raii::DeviceBuffer<uint64_t> deviceReadWindowOffsets(offsetBytes,
																		  "read offsets");
		cuflye::cuda_raii::DeviceBuffer<IndexWindow> deviceIndex(indexBytes, "index");
		cuflye::cuda_raii::DeviceBuffer<RepetitiveWindow> deviceRepetitive(repetitiveBytes,
																		   "repetitive k-mers");
		cuflye::cuda_raii::DeviceBuffer<CandidateRecord> deviceOutput(outputBytes, "output");
		cuflye::cuda_raii::DeviceBuffer<uint8_t> deviceFlags(flagBytes, "flags");

		checkCuda(cudaMemcpy(deviceReads.get(), reads.data(), readBytes, cudaMemcpyHostToDevice),
				  "cudaMemcpy reads host-to-device failed");
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

		const int threadsPerBlock = 128;
		const int blocks = static_cast<int>((pairCount + threadsPerBlock - 1) / threadsPerBlock);
		generateCandidateRecordsKernel<<<blocks, threadsPerBlock>>>(
			deviceReads.get(),
			reads.size(),
			deviceReadWindowOffsets.get(),
			deviceIndex.get(),
			indexEntries.size(),
			deviceRepetitive.get(),
			repetitiveKmers.size(),
			options.kmerSize,
			deviceOutput.get(),
			deviceFlags.get(),
			pairCount);
		checkCuda(cudaGetLastError(), "generateCandidateRecordsKernel launch failed");
		checkCuda(cudaDeviceSynchronize(), "generateCandidateRecordsKernel execution failed");

		std::vector<CandidateRecord> gpuBuffer(pairCount);
		std::vector<uint8_t> validFlags(pairCount);
		checkCuda(cudaMemcpy(gpuBuffer.data(), deviceOutput.get(), outputBytes, cudaMemcpyDeviceToHost),
				  "cudaMemcpy output device-to-host failed");
		checkCuda(cudaMemcpy(validFlags.data(), deviceFlags.get(), flagBytes, cudaMemcpyDeviceToHost),
				  "cudaMemcpy flags device-to-host failed");

		std::vector<CandidateRecord> gpuRecords = compactGpuRecords(gpuBuffer, validFlags);
		writeCandidateTsv(options.outputTsv, gpuRecords);

		std::string json = buildJson(options, prop, freeBytes, totalBytes, requiredBytes,
									 reads.size(), queryWindows, indexEntries.size(),
									 repetitiveKmers.size(), pairCount, gpuRecords.size());
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
