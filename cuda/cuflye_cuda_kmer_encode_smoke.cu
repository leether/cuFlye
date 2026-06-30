// SPDX-License-Identifier: BSD-3-Clause

#include <cuda_runtime_api.h>

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

struct QueryWindow
{
	int64_t queryId;
	uint64_t queryPos;
	char sequence[MAX_KMER_SIZE + 1];
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
	std::string queryTsv;
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

__host__ __device__ uint64_t encodeKmer(const char* sequence, uint32_t kmerSize)
{
	uint64_t representation = 0;
	for (uint32_t index = 0; index < kmerSize; ++index)
	{
		representation <<= 2;
		representation += dnaBaseToBits(sequence[index]);
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
		uint64_t repetitive = standardForm(encodeKmer(repetitiveKmers[index].sequence, kmerSize),
										   kmerSize);
		if (repetitive == lookupKmer) return true;
	}
	return false;
}

__global__ void generateCandidateRecordsKernel(const QueryWindow* queries,
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

	size_t queryIndex = pairIndex / indexCount;
	size_t targetIndex = pairIndex % indexCount;

	QueryWindow query = queries[queryIndex];
	IndexWindow target = indexEntries[targetIndex];
	uint64_t queryKmer = encodeKmer(query.sequence, kmerSize);
	uint64_t queryLookupKmer = standardForm(queryKmer, kmerSize);

	if (isRepetitiveLookupKmer(queryLookupKmer, repetitiveKmers, repetitiveCount, kmerSize))
	{
		validFlags[pairIndex] = 0;
		return;
	}

	uint64_t targetLookupKmer = standardForm(encodeKmer(target.sequence, kmerSize), kmerSize);
	if (queryLookupKmer != targetLookupKmer)
	{
		validFlags[pairIndex] = 0;
		return;
	}

	if (query.queryId == target.targetId && query.queryPos == target.targetPos)
	{
		validFlags[pairIndex] = 0;
		return;
	}

	CandidateRecord record;
	record.queryId = query.queryId;
	record.queryPos = query.queryPos;
	record.kmer = queryKmer;
	record.targetId = target.targetId;
	record.targetPos = target.targetPos;
	record.targetStrand = target.targetStrand;
	for (char& ch : record.padding) ch = 0;
	output[pairIndex] = record;
	validFlags[pairIndex] = 1;
}

[[noreturn]] void usageError(const std::string& message)
{
	throw std::runtime_error(message +
		"\nUsage: cuflye-cuda-kmer-encode-smoke --kmer-size N --queries-tsv PATH "
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
		else if (arg == "--queries-tsv")
		{
			options.queryTsv = requireValue(arg);
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
				<< "Usage: cuflye-cuda-kmer-encode-smoke --kmer-size N "
				<< "--queries-tsv PATH --index-tsv PATH --output-tsv PATH "
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
	if (options.queryTsv.empty()) usageError("--queries-tsv is required");
	if (options.indexTsv.empty()) usageError("--index-tsv is required");
	if (options.outputTsv.empty()) usageError("--output-tsv is required");
	return options;
}

void checkCuda(cudaError_t status, const std::string& action)
{
	if (status != cudaSuccess)
	{
		throw std::runtime_error(action + ": " + cudaGetErrorString(status));
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
						 uint32_t kmerSize,
						 const std::string& path,
						 size_t lineNumber)
{
	if (sequence.size() != kmerSize)
	{
		throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
								 ": sequence length must equal k-mer size");
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

void copySequence(char* destination, const std::string& sequence)
{
	std::memset(destination, 0, MAX_KMER_SIZE + 1);
	std::memcpy(destination, sequence.data(), sequence.size());
}

std::vector<QueryWindow> readQueries(const std::string& path, uint32_t kmerSize)
{
	std::ifstream input(path);
	if (!input) throw std::runtime_error("Can't open query TSV: " + path);

	std::vector<QueryWindow> queries;
	std::string line;
	size_t lineNumber = 0;
	while (std::getline(input, line))
	{
		++lineNumber;
		std::vector<std::string> fields = parseLineFields(line, lineNumber, path, 3);
		validateDnaSequence(fields[2], kmerSize, path, lineNumber);
		QueryWindow query;
		std::memset(&query, 0, sizeof(query));
		query.queryId = parseInt64Field(fields[0], "query_id");
		query.queryPos = parseUint64Field(fields[1], "query_pos");
		copySequence(query.sequence, fields[2]);
		queries.push_back(query);
	}
	if (queries.empty()) throw std::runtime_error("query TSV is empty: " + path);
	return queries;
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
		validateDnaSequence(fields[3], kmerSize, path, lineNumber);
		IndexWindow entry;
		std::memset(&entry, 0, sizeof(entry));
		entry.targetId = parseInt64Field(fields[0], "target_id");
		entry.targetPos = parseUint64Field(fields[1], "target_pos");
		entry.targetStrand = fields[2][0];
		copySequence(entry.sequence, fields[3]);
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
		validateDnaSequence(fields[0], kmerSize, path, lineNumber);
		RepetitiveWindow repetitiveKmer;
		std::memset(&repetitiveKmer, 0, sizeof(repetitiveKmer));
		copySequence(repetitiveKmer.sequence, fields[0]);
		repetitive.push_back(repetitiveKmer);
	}
	return repetitive;
}

bool hostIsRepetitive(uint64_t lookupKmer,
					  const std::vector<RepetitiveWindow>& repetitiveKmers,
					  uint32_t kmerSize)
{
	for (const RepetitiveWindow& repetitive : repetitiveKmers)
	{
		uint64_t repetitiveLookup = standardForm(encodeKmer(repetitive.sequence, kmerSize),
												 kmerSize);
		if (repetitiveLookup == lookupKmer) return true;
	}
	return false;
}

std::vector<CandidateRecord> generateCpuOracle(const std::vector<QueryWindow>& queries,
											   const std::vector<IndexWindow>& indexEntries,
											   const std::vector<RepetitiveWindow>& repetitiveKmers,
											   uint32_t kmerSize)
{
	std::vector<CandidateRecord> records;
	for (const QueryWindow& query : queries)
	{
		uint64_t queryKmer = encodeKmer(query.sequence, kmerSize);
		uint64_t queryLookupKmer = standardForm(queryKmer, kmerSize);
		if (hostIsRepetitive(queryLookupKmer, repetitiveKmers, kmerSize)) continue;
		for (const IndexWindow& target : indexEntries)
		{
			uint64_t targetLookupKmer = standardForm(encodeKmer(target.sequence, kmerSize),
													 kmerSize);
			if (queryLookupKmer != targetLookupKmer) continue;
			if (query.queryId == target.targetId && query.queryPos == target.targetPos) continue;

			CandidateRecord record;
			std::memset(&record, 0, sizeof(record));
			record.queryId = query.queryId;
			record.queryPos = query.queryPos;
			record.kmer = queryKmer;
			record.targetId = target.targetId;
			record.targetPos = target.targetPos;
			record.targetStrand = target.targetStrand;
			records.push_back(record);
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
					  size_t queryCount,
					  size_t indexCount,
					  size_t repetitiveCount,
					  size_t pairCount,
					  size_t outputCount)
{
	std::ostringstream json;
	json << "{\n";
	json << "  \"adapter\": \"cuda-kmer-encode-smoke-v0\",\n";
	json << "  \"status\": \"ok\",\n";
	json << "  \"abi\": \"candidate-record-v1\",\n";
	json << "  \"device\": " << options.device << ",\n";
	json << "  \"device_name\": \"" << jsonEscape(prop.name) << "\",\n";
	json << "  \"compute_capability\": \"" << prop.major << "." << prop.minor << "\",\n";
	json << "  \"kmer_size\": " << options.kmerSize << ",\n";
	json << "  \"queries\": " << queryCount << ",\n";
	json << "  \"index_entries\": " << indexCount << ",\n";
	json << "  \"repetitive_kmers\": " << repetitiveCount << ",\n";
	json << "  \"pair_count\": " << pairCount << ",\n";
	json << "  \"records\": " << outputCount << ",\n";
	json << "  \"query_record_size_bytes\": " << sizeof(QueryWindow) << ",\n";
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
	json << "  \"device_side_kmer_encoding\": true,\n";
	json << "  \"device_side_standard_form\": true,\n";
	json << "  \"queries_tsv\": \"" << jsonEscape(options.queryTsv) << "\",\n";
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
		std::vector<QueryWindow> queries = readQueries(options.queryTsv, options.kmerSize);
		std::vector<IndexWindow> indexEntries = readIndex(options.indexTsv, options.kmerSize);
		std::vector<RepetitiveWindow> repetitiveKmers =
			readRepetitiveKmers(options.repetitiveTsv, options.kmerSize);

		size_t pairCount = checkedMultiply(queries.size(), indexEntries.size(), "query/index pair");
		if (pairCount == 0) throw std::runtime_error("query/index pair count is zero");

		std::vector<CandidateRecord> cpuRecords =
			generateCpuOracle(queries, indexEntries, repetitiveKmers, options.kmerSize);
		if (cpuRecords.empty()) throw std::runtime_error("CPU oracle emitted no candidate records");
		writeCandidateTsv(options.cpuOutputTsv, cpuRecords);

		checkCuda(cudaSetDevice(options.device), "cudaSetDevice failed");
		cudaDeviceProp prop;
		std::memset(&prop, 0, sizeof(prop));
		checkCuda(cudaGetDeviceProperties(&prop, options.device), "cudaGetDeviceProperties failed");

		size_t freeBytes = 0;
		size_t totalBytes = 0;
		checkCuda(cudaMemGetInfo(&freeBytes, &totalBytes), "cudaMemGetInfo failed");

		size_t queryBytes = checkedMultiply(queries.size(), sizeof(QueryWindow), "query buffer");
		size_t indexBytes = checkedMultiply(indexEntries.size(), sizeof(IndexWindow), "index buffer");
		size_t repetitiveBytes = checkedMultiply(repetitiveKmers.size(), sizeof(RepetitiveWindow),
												 "repetitive k-mer buffer");
		size_t outputBytes = checkedMultiply(pairCount, sizeof(CandidateRecord), "output buffer");
		size_t flagBytes = checkedMultiply(pairCount, sizeof(uint8_t), "valid flag buffer");
		size_t requiredBytes = checkedAdd(queryBytes, indexBytes, "device allocation");
		requiredBytes = checkedAdd(requiredBytes, repetitiveBytes, "device allocation");
		requiredBytes = checkedAdd(requiredBytes, outputBytes, "device allocation");
		requiredBytes = checkedAdd(requiredBytes, flagBytes, "device allocation");

		if (options.hasMemoryBudget && requiredBytes > options.memoryBudgetBytes)
		{
			throw std::runtime_error("CUDA k-mer encode smoke memory budget is smaller than required device allocation");
		}
		if (requiredBytes > freeBytes)
		{
			throw std::runtime_error("CUDA k-mer encode smoke required device allocation exceeds free device memory");
		}

		QueryWindow* deviceQueries = nullptr;
		IndexWindow* deviceIndex = nullptr;
		RepetitiveWindow* deviceRepetitive = nullptr;
		CandidateRecord* deviceOutput = nullptr;
		uint8_t* deviceFlags = nullptr;

		checkCuda(cudaMalloc(&deviceQueries, queryBytes), "cudaMalloc queries failed");
		checkCuda(cudaMalloc(&deviceIndex, indexBytes), "cudaMalloc index failed");
		if (repetitiveBytes)
		{
			checkCuda(cudaMalloc(&deviceRepetitive, repetitiveBytes),
					  "cudaMalloc repetitive k-mers failed");
		}
		checkCuda(cudaMalloc(&deviceOutput, outputBytes), "cudaMalloc output failed");
		checkCuda(cudaMalloc(&deviceFlags, flagBytes), "cudaMalloc flags failed");

		checkCuda(cudaMemcpy(deviceQueries, queries.data(), queryBytes, cudaMemcpyHostToDevice),
				  "cudaMemcpy queries host-to-device failed");
		checkCuda(cudaMemcpy(deviceIndex, indexEntries.data(), indexBytes, cudaMemcpyHostToDevice),
				  "cudaMemcpy index host-to-device failed");
		if (repetitiveBytes)
		{
			checkCuda(cudaMemcpy(deviceRepetitive, repetitiveKmers.data(), repetitiveBytes,
								 cudaMemcpyHostToDevice),
					  "cudaMemcpy repetitive k-mers host-to-device failed");
		}
		checkCuda(cudaMemset(deviceFlags, 0, flagBytes), "cudaMemset flags failed");

		const int threadsPerBlock = 128;
		const int blocks = static_cast<int>((pairCount + threadsPerBlock - 1) / threadsPerBlock);
		generateCandidateRecordsKernel<<<blocks, threadsPerBlock>>>(
			deviceQueries,
			deviceIndex,
			indexEntries.size(),
			deviceRepetitive,
			repetitiveKmers.size(),
			options.kmerSize,
			deviceOutput,
			deviceFlags,
			pairCount);
		checkCuda(cudaGetLastError(), "generateCandidateRecordsKernel launch failed");
		checkCuda(cudaDeviceSynchronize(), "generateCandidateRecordsKernel execution failed");

		std::vector<CandidateRecord> gpuBuffer(pairCount);
		std::vector<uint8_t> validFlags(pairCount);
		checkCuda(cudaMemcpy(gpuBuffer.data(), deviceOutput, outputBytes, cudaMemcpyDeviceToHost),
				  "cudaMemcpy output device-to-host failed");
		checkCuda(cudaMemcpy(validFlags.data(), deviceFlags, flagBytes, cudaMemcpyDeviceToHost),
				  "cudaMemcpy flags device-to-host failed");

		checkCuda(cudaFree(deviceQueries), "cudaFree queries failed");
		checkCuda(cudaFree(deviceIndex), "cudaFree index failed");
		if (deviceRepetitive) checkCuda(cudaFree(deviceRepetitive), "cudaFree repetitive failed");
		checkCuda(cudaFree(deviceOutput), "cudaFree output failed");
		checkCuda(cudaFree(deviceFlags), "cudaFree flags failed");

		std::vector<CandidateRecord> gpuRecords = compactGpuRecords(gpuBuffer, validFlags);
		writeCandidateTsv(options.outputTsv, gpuRecords);

		std::string json = buildJson(options, prop, freeBytes, totalBytes, requiredBytes,
									 queries.size(), indexEntries.size(),
									 repetitiveKmers.size(), pairCount, gpuRecords.size());
		writeText(options.jsonOutput, json);
		std::cout << json;
		return 0;
	}
	catch (const std::exception& exc)
	{
		std::cerr << "cuFlye CUDA k-mer encode smoke failed: " << exc.what() << "\n";
		return 1;
	}
}
