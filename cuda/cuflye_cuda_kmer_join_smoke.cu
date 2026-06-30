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
struct QueryKmer
{
	int64_t queryId;
	uint64_t queryPos;
	uint64_t queryKmer;
	uint64_t lookupKmer;
};

struct IndexEntry
{
	uint64_t lookupKmer;
	int64_t targetId;
	uint64_t targetPos;
	char targetStrand;
	char padding[7];
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
	int device = 0;
	bool hasMemoryBudget = false;
	unsigned long long memoryBudgetBytes = 0;
};

__device__ bool isRepetitiveLookupKmer(uint64_t lookupKmer,
									   const uint64_t* repetitiveKmers,
									   size_t repetitiveCount)
{
	for (size_t index = 0; index < repetitiveCount; ++index)
	{
		if (repetitiveKmers[index] == lookupKmer) return true;
	}
	return false;
}

__global__ void generateCandidateRecordsKernel(const QueryKmer* queries,
											   size_t queryCount,
											   const IndexEntry* indexEntries,
											   size_t indexCount,
											   const uint64_t* repetitiveKmers,
											   size_t repetitiveCount,
											   CandidateRecord* output,
											   uint8_t* validFlags,
											   size_t pairCount)
{
	size_t pairIndex = static_cast<size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
	if (pairIndex >= pairCount) return;

	size_t queryIndex = pairIndex / indexCount;
	size_t targetIndex = pairIndex % indexCount;

	QueryKmer query = queries[queryIndex];
	IndexEntry target = indexEntries[targetIndex];

	if (isRepetitiveLookupKmer(query.lookupKmer, repetitiveKmers, repetitiveCount))
	{
		validFlags[pairIndex] = 0;
		return;
	}

	if (query.lookupKmer != target.lookupKmer)
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
	record.kmer = query.queryKmer;
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
		"\nUsage: cuflye-cuda-kmer-join-smoke --queries-tsv PATH --index-tsv PATH "
		"--output-tsv PATH [--repetitive-kmers-tsv PATH] [--cpu-output-tsv PATH] "
		"[--device N] [--memory-budget-bytes N] [--json-output PATH]");
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

		if (arg == "--queries-tsv")
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
				<< "Usage: cuflye-cuda-kmer-join-smoke --queries-tsv PATH "
				<< "--index-tsv PATH --output-tsv PATH [--repetitive-kmers-tsv PATH] "
				<< "[--cpu-output-tsv PATH] [--device N] [--memory-budget-bytes N] "
				<< "[--json-output PATH]\n";
			std::exit(0);
		}
		else
		{
			usageError("Unknown option: " + arg);
		}
	}

	if (options.queryTsv.empty()) usageError("--queries-tsv is required");
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

std::vector<QueryKmer> readQueries(const std::string& path)
{
	std::ifstream input(path);
	if (!input) throw std::runtime_error("Can't open query TSV: " + path);

	std::vector<QueryKmer> queries;
	std::string line;
	size_t lineNumber = 0;
	while (std::getline(input, line))
	{
		++lineNumber;
		std::vector<std::string> fields = parseLineFields(line, lineNumber, path, 4);
		QueryKmer query;
		query.queryId = parseInt64Field(fields[0], "query_id");
		query.queryPos = parseUint64Field(fields[1], "query_pos");
		query.queryKmer = parseUint64Field(fields[2], "query_kmer");
		query.lookupKmer = parseUint64Field(fields[3], "lookup_kmer");
		queries.push_back(query);
	}
	if (queries.empty()) throw std::runtime_error("query TSV is empty: " + path);
	return queries;
}

std::vector<IndexEntry> readIndex(const std::string& path)
{
	std::ifstream input(path);
	if (!input) throw std::runtime_error("Can't open index TSV: " + path);

	std::vector<IndexEntry> entries;
	std::string line;
	size_t lineNumber = 0;
	while (std::getline(input, line))
	{
		++lineNumber;
		std::vector<std::string> fields = parseLineFields(line, lineNumber, path, 4);
		if (fields[3] != "+" && fields[3] != "-")
		{
			throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
									 ": target_strand must be '+' or '-'");
		}
		IndexEntry entry;
		std::memset(&entry, 0, sizeof(entry));
		entry.lookupKmer = parseUint64Field(fields[0], "lookup_kmer");
		entry.targetId = parseInt64Field(fields[1], "target_id");
		entry.targetPos = parseUint64Field(fields[2], "target_pos");
		entry.targetStrand = fields[3][0];
		entries.push_back(entry);
	}
	if (entries.empty()) throw std::runtime_error("index TSV is empty: " + path);
	return entries;
}

std::vector<uint64_t> readRepetitiveKmers(const std::string& path)
{
	std::vector<uint64_t> repetitive;
	if (path.empty()) return repetitive;

	std::ifstream input(path);
	if (!input) throw std::runtime_error("Can't open repetitive k-mer TSV: " + path);

	std::string line;
	size_t lineNumber = 0;
	while (std::getline(input, line))
	{
		++lineNumber;
		std::vector<std::string> fields = parseLineFields(line, lineNumber, path, 1);
		repetitive.push_back(parseUint64Field(fields[0], "lookup_kmer"));
	}
	return repetitive;
}

bool hostIsRepetitive(uint64_t lookupKmer, const std::vector<uint64_t>& repetitiveKmers)
{
	for (uint64_t repetitive : repetitiveKmers)
	{
		if (repetitive == lookupKmer) return true;
	}
	return false;
}

std::vector<CandidateRecord> generateCpuOracle(const std::vector<QueryKmer>& queries,
											   const std::vector<IndexEntry>& indexEntries,
											   const std::vector<uint64_t>& repetitiveKmers)
{
	std::vector<CandidateRecord> records;
	for (const QueryKmer& query : queries)
	{
		if (hostIsRepetitive(query.lookupKmer, repetitiveKmers)) continue;
		for (const IndexEntry& target : indexEntries)
		{
			if (query.lookupKmer != target.lookupKmer) continue;
			if (query.queryId == target.targetId && query.queryPos == target.targetPos) continue;

			CandidateRecord record;
			std::memset(&record, 0, sizeof(record));
			record.queryId = query.queryId;
			record.queryPos = query.queryPos;
			record.kmer = query.queryKmer;
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
	json << "  \"adapter\": \"cuda-kmer-join-smoke-v0\",\n";
	json << "  \"status\": \"ok\",\n";
	json << "  \"abi\": \"candidate-record-v1\",\n";
	json << "  \"device\": " << options.device << ",\n";
	json << "  \"device_name\": \"" << jsonEscape(prop.name) << "\",\n";
	json << "  \"compute_capability\": \"" << prop.major << "." << prop.minor << "\",\n";
	json << "  \"queries\": " << queryCount << ",\n";
	json << "  \"index_entries\": " << indexCount << ",\n";
	json << "  \"repetitive_kmers\": " << repetitiveCount << ",\n";
	json << "  \"pair_count\": " << pairCount << ",\n";
	json << "  \"records\": " << outputCount << ",\n";
	json << "  \"query_record_size_bytes\": " << sizeof(QueryKmer) << ",\n";
	json << "  \"index_record_size_bytes\": " << sizeof(IndexEntry) << ",\n";
	json << "  \"candidate_record_size_bytes\": " << sizeof(CandidateRecord) << ",\n";
	json << "  \"device_allocation_bytes\": " << requiredBytes << ",\n";
	json << "  \"memory_free_bytes\": " << static_cast<unsigned long long>(freeBytes) << ",\n";
	json << "  \"memory_total_bytes\": " << static_cast<unsigned long long>(totalBytes) << ",\n";
	json << "  \"memory_budget_bytes\": ";
	if (options.hasMemoryBudget) json << options.memoryBudgetBytes;
	else json << "null";
	json << ",\n";
	json << "  \"memory_budget_satisfied\": true,\n";
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
		std::vector<QueryKmer> queries = readQueries(options.queryTsv);
		std::vector<IndexEntry> indexEntries = readIndex(options.indexTsv);
		std::vector<uint64_t> repetitiveKmers = readRepetitiveKmers(options.repetitiveTsv);

		size_t pairCount = checkedMultiply(queries.size(), indexEntries.size(), "query/index pair");
		if (pairCount == 0) throw std::runtime_error("query/index pair count is zero");

		std::vector<CandidateRecord> cpuRecords =
			generateCpuOracle(queries, indexEntries, repetitiveKmers);
		if (cpuRecords.empty()) throw std::runtime_error("CPU oracle emitted no candidate records");
		writeCandidateTsv(options.cpuOutputTsv, cpuRecords);

		checkCuda(cudaSetDevice(options.device), "cudaSetDevice failed");
		cudaDeviceProp prop;
		std::memset(&prop, 0, sizeof(prop));
		checkCuda(cudaGetDeviceProperties(&prop, options.device), "cudaGetDeviceProperties failed");

		size_t freeBytes = 0;
		size_t totalBytes = 0;
		checkCuda(cudaMemGetInfo(&freeBytes, &totalBytes), "cudaMemGetInfo failed");

		size_t queryBytes = checkedMultiply(queries.size(), sizeof(QueryKmer), "query buffer");
		size_t indexBytes = checkedMultiply(indexEntries.size(), sizeof(IndexEntry), "index buffer");
		size_t repetitiveBytes = checkedMultiply(repetitiveKmers.size(), sizeof(uint64_t),
												 "repetitive k-mer buffer");
		size_t outputBytes = checkedMultiply(pairCount, sizeof(CandidateRecord), "output buffer");
		size_t flagBytes = checkedMultiply(pairCount, sizeof(uint8_t), "valid flag buffer");
		size_t requiredBytes = checkedAdd(queryBytes, indexBytes, "device allocation");
		requiredBytes = checkedAdd(requiredBytes, repetitiveBytes, "device allocation");
		requiredBytes = checkedAdd(requiredBytes, outputBytes, "device allocation");
		requiredBytes = checkedAdd(requiredBytes, flagBytes, "device allocation");

		if (options.hasMemoryBudget && requiredBytes > options.memoryBudgetBytes)
		{
			throw std::runtime_error("CUDA k-mer join smoke memory budget is smaller than required device allocation");
		}
		if (requiredBytes > freeBytes)
		{
			throw std::runtime_error("CUDA k-mer join smoke required device allocation exceeds free device memory");
		}

		cuflye::cuda_raii::DeviceBuffer<QueryKmer> deviceQueries(queryBytes, "queries");
		cuflye::cuda_raii::DeviceBuffer<IndexEntry> deviceIndex(indexBytes, "index");
		cuflye::cuda_raii::DeviceBuffer<uint64_t> deviceRepetitive(repetitiveBytes,
																   "repetitive k-mers");
		cuflye::cuda_raii::DeviceBuffer<CandidateRecord> deviceOutput(outputBytes, "output");
		cuflye::cuda_raii::DeviceBuffer<uint8_t> deviceFlags(flagBytes, "flags");

		checkCuda(cudaMemcpy(deviceQueries.get(), queries.data(), queryBytes, cudaMemcpyHostToDevice),
				  "cudaMemcpy queries host-to-device failed");
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
			deviceQueries.get(),
			queries.size(),
			deviceIndex.get(),
			indexEntries.size(),
			deviceRepetitive.get(),
			repetitiveKmers.size(),
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
									 queries.size(), indexEntries.size(),
									 repetitiveKmers.size(), pairCount, gpuRecords.size());
		writeText(options.jsonOutput, json);
		std::cout << json;
		return 0;
	}
	catch (const std::exception& exc)
	{
		std::cerr << "cuFlye CUDA k-mer join smoke failed: " << exc.what() << "\n";
		return 1;
	}
}
