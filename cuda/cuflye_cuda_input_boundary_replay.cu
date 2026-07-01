// SPDX-License-Identifier: BSD-3-Clause

#include <cuda_runtime_api.h>

#include "cuflye_cuda_raii.hpp"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <limits>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace
{
using Clock = std::chrono::steady_clock;

struct RawOverlapRecord
{
	int64_t queryId;
	int32_t queryOrdinal;
	int32_t sourceOrder;
	int32_t rawOverlapCount;
	int32_t chainInputCount;
	int64_t readId;
	int32_t readBegin;
	int32_t readEnd;
	int32_t readLen;
	int64_t edgeSeqId;
	int32_t edgeBegin;
	int32_t edgeEnd;
	int32_t edgeLen;
	int64_t edgeId;
	int32_t score;
	float seqDivergence;
	int32_t passesChainInputFilter;
};

struct ChainInputRecord
{
	int64_t queryId;
	int32_t order;
	int32_t rawOverlapCount;
	int32_t chainInputCount;
	int64_t readId;
	int32_t readBegin;
	int32_t readEnd;
	int32_t readLen;
	int64_t edgeSeqId;
	int32_t edgeBegin;
	int32_t edgeEnd;
	int32_t edgeLen;
	int64_t edgeId;
	int32_t score;
	float seqDivergence;
	int32_t passesChainInputFilter;
};

struct QuerySummary
{
	int64_t queryId = 0;
	int32_t rawOverlapCount = 0;
	int32_t chainInputCount = 0;
	int32_t outputOffset = 0;
};

struct DeviceStatus
{
	int32_t errorCode;
	int32_t outputRecords;
};

struct Options
{
	std::string packDir;
	std::string outputTsv;
	std::string jsonOutput;
	int device = 0;
	bool hasMemoryBudget = false;
	unsigned long long memoryBudgetBytes = 0;
};

struct RunSummary
{
	double parseMs = 0.0;
	double hostPackMs = 0.0;
	double deviceAllocationMs = 0.0;
	double hostToDeviceMs = 0.0;
	double kernelMs = 0.0;
	double deviceToHostMs = 0.0;
	double writeMs = 0.0;
	double totalMs = 0.0;
	size_t queryCount = 0;
	size_t rawOverlapRecords = 0;
	size_t outputRecords = 0;
	size_t requiredBytes = 0;
	size_t freeBytes = 0;
	size_t totalBytes = 0;
	int device = 0;
	std::string deviceName;
};

double elapsedMs(Clock::time_point start, Clock::time_point end)
{
	return std::chrono::duration<double, std::milli>(end - start).count();
}

std::vector<std::string> splitTab(const std::string& line)
{
	std::vector<std::string> fields;
	std::stringstream stream(line);
	std::string field;
	while (std::getline(stream, field, '\t')) fields.push_back(field);
	return fields;
}

int64_t parseI64(const std::string& text, const std::string& name)
{
	size_t parsed = 0;
	long long value = std::stoll(text, &parsed);
	if (parsed != text.size())
	{
		throw std::runtime_error(name + " must be a decimal integer");
	}
	return static_cast<int64_t>(value);
}

int32_t parseI32(const std::string& text, const std::string& name)
{
	int64_t value = parseI64(text, name);
	if (value < std::numeric_limits<int32_t>::min() ||
		value > std::numeric_limits<int32_t>::max())
	{
		throw std::runtime_error(name + " is outside int32 range");
	}
	return static_cast<int32_t>(value);
}

float parseF32(const std::string& text, const std::string& name)
{
	size_t parsed = 0;
	float value = std::stof(text, &parsed);
	if (parsed != text.size())
	{
		throw std::runtime_error(name + " must be a float");
	}
	return value;
}

std::string joinPath(const std::string& left, const std::string& right)
{
	if (left.empty()) return right;
	if (left[left.size() - 1] == '/') return left + right;
	return left + "/" + right;
}

void requireSchemaLine(std::ifstream& input, const std::string& path,
					   const std::string& expected)
{
	std::string line;
	if (!std::getline(input, line) || line != expected)
	{
		throw std::runtime_error(path + ": unexpected schema line");
	}
}

void requireHeaderLine(std::ifstream& input, const std::string& path,
					   const std::string& expected)
{
	std::string line;
	if (!std::getline(input, line) || line != expected)
	{
		throw std::runtime_error(path + ": unexpected header line");
	}
}

void validatePackManifest(const std::string& packDir)
{
	std::string path = joinPath(packDir, "manifest.json");
	std::ifstream input(path.c_str());
	if (!input)
	{
		throw std::runtime_error("can't open pack manifest: " + path);
	}
	std::string text((std::istreambuf_iterator<char>(input)),
					 std::istreambuf_iterator<char>());
	if (text.find("\"schema\": \"cuflye-read-to-graph-input-boundary-replay-pack-v0\"") ==
		std::string::npos)
	{
		throw std::runtime_error(path + ": unsupported pack schema");
	}
}

std::vector<QuerySummary> loadQueries(const std::string& packDir)
{
	std::string path = joinPath(packDir, "queries.tsv");
	std::ifstream input(path.c_str());
	if (!input)
	{
		throw std::runtime_error("can't open queries TSV: " + path);
	}
	requireSchemaLine(input, path,
					  "# schema=cuflye-read-to-graph-input-boundary-query-v0");
	requireHeaderLine(
		input, path,
		"query_id\traw_overlap_count\tchain_input_count\t"
		"filtered_out_raw_overlap_count\tquick_overlap_wall_ms\t"
		"input_filter_sort_wall_ms\tcpu_chain_dp_wall_ms\t"
		"cpu_divergence_filter_wall_ms");

	std::vector<QuerySummary> queries;
	std::string line;
	int32_t outputOffset = 0;
	while (std::getline(input, line))
	{
		auto fields = splitTab(line);
		if (fields.size() != 8)
		{
			throw std::runtime_error(path + ": query row must have 8 fields");
		}
		QuerySummary query;
		query.queryId = parseI64(fields[0], "query_id");
		query.rawOverlapCount = parseI32(fields[1], "raw_overlap_count");
		query.chainInputCount = parseI32(fields[2], "chain_input_count");
		if (query.rawOverlapCount <= 0 || query.chainInputCount <= 0)
		{
			throw std::runtime_error(path + ": selected queries must be non-empty");
		}
		query.outputOffset = outputOffset;
		outputOffset += query.chainInputCount;
		queries.push_back(query);
	}
	if (queries.empty())
	{
		throw std::runtime_error(path + ": query set is empty");
	}
	return queries;
}

std::vector<RawOverlapRecord>
loadRawOverlaps(const std::string& packDir,
				const std::vector<QuerySummary>& queries)
{
	std::map<int64_t, int32_t> queryOrdinals;
	for (size_t idx = 0; idx < queries.size(); ++idx)
	{
		queryOrdinals[queries[idx].queryId] = static_cast<int32_t>(idx);
	}

	std::string path = joinPath(packDir, "raw-overlaps.tsv");
	std::ifstream input(path.c_str());
	if (!input)
	{
		throw std::runtime_error("can't open raw overlaps TSV: " + path);
	}
	requireSchemaLine(input, path, "# schema=cuflye-read-to-graph-raw-overlap-v0");
	requireHeaderLine(
		input, path,
		"query_id\tsource_order\traw_overlap_count\tchain_input_count\tread_id\t"
		"read_begin\tread_end\tread_len\tedge_seq_id\tedge_begin\tedge_end\t"
		"edge_len\tedge_id\tscore\tseq_divergence\tpasses_chain_input_filter");

	std::vector<RawOverlapRecord> raw;
	std::string line;
	while (std::getline(input, line))
	{
		auto fields = splitTab(line);
		if (fields.size() != 16)
		{
			throw std::runtime_error(path + ": raw overlap row must have 16 fields");
		}
		RawOverlapRecord record;
		record.queryId = parseI64(fields[0], "query_id");
		auto query = queryOrdinals.find(record.queryId);
		if (query == queryOrdinals.end())
		{
			throw std::runtime_error(path + ": raw overlap has unknown query_id");
		}
		record.queryOrdinal = query->second;
		record.sourceOrder = parseI32(fields[1], "source_order");
		record.rawOverlapCount = parseI32(fields[2], "raw_overlap_count");
		record.chainInputCount = parseI32(fields[3], "chain_input_count");
		record.readId = parseI64(fields[4], "read_id");
		record.readBegin = parseI32(fields[5], "read_begin");
		record.readEnd = parseI32(fields[6], "read_end");
		record.readLen = parseI32(fields[7], "read_len");
		record.edgeSeqId = parseI64(fields[8], "edge_seq_id");
		record.edgeBegin = parseI32(fields[9], "edge_begin");
		record.edgeEnd = parseI32(fields[10], "edge_end");
		record.edgeLen = parseI32(fields[11], "edge_len");
		record.edgeId = parseI64(fields[12], "edge_id");
		record.score = parseI32(fields[13], "score");
		record.seqDivergence = parseF32(fields[14], "seq_divergence");
		record.passesChainInputFilter =
			parseI32(fields[15], "passes_chain_input_filter");
		if (record.passesChainInputFilter != 0 &&
			record.passesChainInputFilter != 1)
		{
			throw std::runtime_error(path + ": passes_chain_input_filter must be 0 or 1");
		}
		raw.push_back(record);
	}
	if (raw.empty())
	{
		throw std::runtime_error(path + ": raw overlap set is empty");
	}
	return raw;
}

void validateHostShape(const std::vector<QuerySummary>& queries,
					   const std::vector<RawOverlapRecord>& raw)
{
	std::vector<int32_t> rawCounts(queries.size(), 0);
	std::vector<int32_t> passedCounts(queries.size(), 0);
	std::vector<std::vector<int32_t>> readBegins(queries.size());
	for (const auto& record : raw)
	{
		rawCounts[record.queryOrdinal] += 1;
		if (record.passesChainInputFilter)
		{
			passedCounts[record.queryOrdinal] += 1;
			readBegins[record.queryOrdinal].push_back(record.readBegin);
		}
	}
	for (size_t idx = 0; idx < queries.size(); ++idx)
	{
		if (rawCounts[idx] != queries[idx].rawOverlapCount)
		{
			throw std::runtime_error("raw overlap count mismatch for selected query");
		}
		if (passedCounts[idx] != queries[idx].chainInputCount)
		{
			throw std::runtime_error("chain input count mismatch for selected query");
		}
		std::sort(readBegins[idx].begin(), readBegins[idx].end());
		for (size_t pos = 1; pos < readBegins[idx].size(); ++pos)
		{
			if (readBegins[idx][pos] == readBegins[idx][pos - 1])
			{
				throw std::runtime_error(
					"duplicate read_begin makes selected query unsupported");
			}
		}
	}
}

std::vector<int32_t> queryOffsets(const std::vector<QuerySummary>& queries)
{
	std::vector<int32_t> offsets;
	offsets.reserve(queries.size());
	for (const auto& query : queries) offsets.push_back(query.outputOffset);
	return offsets;
}

size_t outputRecordCount(const std::vector<QuerySummary>& queries)
{
	size_t total = 0;
	for (const auto& query : queries) total += query.chainInputCount;
	return total;
}

void writeChainInputTsv(const std::string& path,
						const std::vector<ChainInputRecord>& records)
{
	std::ofstream output(path.c_str());
	if (!output)
	{
		throw std::runtime_error("can't open output TSV: " + path);
	}
	output << "# schema=cuflye-read-to-graph-chain-input-v0\n";
	output << "query_id\torder\traw_overlap_count\tchain_input_count\tread_id\t"
			  "read_begin\tread_end\tread_len\tedge_seq_id\tedge_begin\t"
			  "edge_end\tedge_len\tedge_id\tscore\tseq_divergence\t"
			  "passes_chain_input_filter\n";
	output << std::setprecision(9);
	for (const auto& record : records)
	{
		output << record.queryId << "\t"
			   << record.order << "\t"
			   << record.rawOverlapCount << "\t"
			   << record.chainInputCount << "\t"
			   << record.readId << "\t"
			   << record.readBegin << "\t"
			   << record.readEnd << "\t"
			   << record.readLen << "\t"
			   << record.edgeSeqId << "\t"
			   << record.edgeBegin << "\t"
			   << record.edgeEnd << "\t"
			   << record.edgeLen << "\t"
			   << record.edgeId << "\t"
			   << record.score << "\t"
			   << record.seqDivergence << "\t"
			   << record.passesChainInputFilter << "\n";
	}
}

std::string jsonEscape(const std::string& value)
{
	std::string escaped;
	for (char ch : value)
	{
		switch (ch)
		{
		case '\\': escaped += "\\\\"; break;
		case '"': escaped += "\\\""; break;
		case '\n': escaped += "\\n"; break;
		case '\r': escaped += "\\r"; break;
		case '\t': escaped += "\\t"; break;
		default: escaped += ch; break;
		}
	}
	return escaped;
}

void writeJson(const std::string& path, const Options& options,
			   const RunSummary& summary)
{
	if (path.empty()) return;
	std::ofstream output(path.c_str());
	if (!output)
	{
		throw std::runtime_error("can't open JSON output: " + path);
	}
	output << std::fixed << std::setprecision(6);
	output << "{\n"
		   << "  \"schema\": \"cuflye-cuda-input-boundary-replay-v0\",\n"
		   << "  \"status\": \"ok\",\n"
		   << "  \"backend\": \"cuda\",\n"
		   << "  \"pack_dir\": \"" << jsonEscape(options.packDir) << "\",\n"
		   << "  \"output_tsv\": \"" << jsonEscape(options.outputTsv) << "\",\n"
		   << "  \"device\": " << summary.device << ",\n"
		   << "  \"device_name\": \"" << jsonEscape(summary.deviceName) << "\",\n"
		   << "  \"query_count\": " << summary.queryCount << ",\n"
		   << "  \"raw_overlap_records\": " << summary.rawOverlapRecords << ",\n"
		   << "  \"output_records\": " << summary.outputRecords << ",\n"
		   << "  \"required_bytes\": " << summary.requiredBytes << ",\n"
		   << "  \"free_bytes\": " << summary.freeBytes << ",\n"
		   << "  \"total_bytes\": " << summary.totalBytes << ",\n"
		   << "  \"timing_ms\": {\n"
		   << "    \"parse\": " << summary.parseMs << ",\n"
		   << "    \"host_pack\": " << summary.hostPackMs << ",\n"
		   << "    \"device_allocation\": " << summary.deviceAllocationMs << ",\n"
		   << "    \"host_to_device\": " << summary.hostToDeviceMs << ",\n"
		   << "    \"kernel\": " << summary.kernelMs << ",\n"
		   << "    \"device_to_host\": " << summary.deviceToHostMs << ",\n"
		   << "    \"write_output\": " << summary.writeMs << ",\n"
		   << "    \"total\": " << summary.totalMs << "\n"
		   << "  }\n"
		   << "}\n";
}

Options parseOptions(int argc, char** argv)
{
	Options options;
	for (int i = 1; i < argc; ++i)
	{
		std::string arg = argv[i];
		auto requireValue = [&](const std::string& name) -> std::string {
			if (i + 1 >= argc)
			{
				throw std::runtime_error(name + " requires a value");
			}
			return argv[++i];
		};
		if (arg == "--pack-dir") options.packDir = requireValue(arg);
		else if (arg == "--output-tsv") options.outputTsv = requireValue(arg);
		else if (arg == "--json-output") options.jsonOutput = requireValue(arg);
		else if (arg == "--device") options.device = parseI32(requireValue(arg), arg);
		else if (arg == "--memory-budget-bytes")
		{
			options.hasMemoryBudget = true;
			options.memoryBudgetBytes =
				static_cast<unsigned long long>(parseI64(requireValue(arg), arg));
		}
		else if (arg == "-h" || arg == "--help")
		{
			std::cout << "Usage: cuflye-cuda-input-boundary-replay "
					  << "--pack-dir DIR --output-tsv PATH [--json-output PATH] "
					  << "[--device ID] [--memory-budget-bytes N]\n";
			std::exit(0);
		}
		else
		{
			throw std::runtime_error("unknown option: " + arg);
		}
	}
	if (options.packDir.empty()) throw std::runtime_error("--pack-dir is required");
	if (options.outputTsv.empty()) throw std::runtime_error("--output-tsv is required");
	return options;
}

__global__ void filterSortRawOverlapsKernel(const RawOverlapRecord* raw,
											int32_t rawCount,
											const int32_t* queryOffsets,
											ChainInputRecord* output,
											DeviceStatus* status)
{
	int32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
	if (idx >= rawCount) return;
	RawOverlapRecord record = raw[idx];
	if (!record.passesChainInputFilter) return;

	int32_t rank = 0;
	for (int32_t otherIdx = 0; otherIdx < rawCount; ++otherIdx)
	{
		RawOverlapRecord other = raw[otherIdx];
		if (other.queryOrdinal == record.queryOrdinal &&
			other.passesChainInputFilter &&
			other.readBegin < record.readBegin)
		{
			++rank;
		}
	}
	if (rank < 0 || rank >= record.chainInputCount)
	{
		status->errorCode = 1;
		return;
	}

	int32_t outputIndex = queryOffsets[record.queryOrdinal] + rank;
	ChainInputRecord out;
	out.queryId = record.queryId;
	out.order = rank;
	out.rawOverlapCount = record.rawOverlapCount;
	out.chainInputCount = record.chainInputCount;
	out.readId = record.readId;
	out.readBegin = record.readBegin;
	out.readEnd = record.readEnd;
	out.readLen = record.readLen;
	out.edgeSeqId = record.edgeSeqId;
	out.edgeBegin = record.edgeBegin;
	out.edgeEnd = record.edgeEnd;
	out.edgeLen = record.edgeLen;
	out.edgeId = record.edgeId;
	out.score = record.score;
	out.seqDivergence = record.seqDivergence;
	out.passesChainInputFilter = 1;
	output[outputIndex] = out;
	atomicAdd(&status->outputRecords, 1);
}
}

int main(int argc, char** argv)
{
	try
	{
		auto totalStart = Clock::now();
		Options options = parseOptions(argc, argv);
		RunSummary summary;
		summary.device = options.device;

		auto parseStart = Clock::now();
		validatePackManifest(options.packDir);
		std::vector<QuerySummary> queries = loadQueries(options.packDir);
		std::vector<RawOverlapRecord> raw = loadRawOverlaps(options.packDir, queries);
		validateHostShape(queries, raw);
		summary.parseMs = elapsedMs(parseStart, Clock::now());

		auto hostPackStart = Clock::now();
		std::vector<int32_t> offsets = queryOffsets(queries);
		size_t outputCount = outputRecordCount(queries);
		std::vector<ChainInputRecord> output(outputCount);
		DeviceStatus zeroStatus{0, 0};
		summary.hostPackMs = elapsedMs(hostPackStart, Clock::now());

		cuflye::cuda_raii::checkCuda(
			cudaSetDevice(options.device), "select CUDA device");
		cudaDeviceProp props{};
		cuflye::cuda_raii::checkCuda(
			cudaGetDeviceProperties(&props, options.device),
			"read CUDA device properties");
		summary.deviceName = props.name;
		cuflye::cuda_raii::checkCuda(
			cudaMemGetInfo(&summary.freeBytes, &summary.totalBytes),
			"read CUDA memory info");

		summary.queryCount = queries.size();
		summary.rawOverlapRecords = raw.size();
		summary.outputRecords = outputCount;
		summary.requiredBytes =
			raw.size() * sizeof(RawOverlapRecord) +
			offsets.size() * sizeof(int32_t) +
			output.size() * sizeof(ChainInputRecord) +
			sizeof(DeviceStatus);
		if (options.hasMemoryBudget &&
			summary.requiredBytes > options.memoryBudgetBytes)
		{
			throw std::runtime_error("required bytes exceed memory budget");
		}

		auto allocStart = Clock::now();
		cuflye::cuda_raii::DeviceBuffer<RawOverlapRecord> dRaw(
			raw.size() * sizeof(RawOverlapRecord), "input boundary raw overlaps");
		cuflye::cuda_raii::DeviceBuffer<int32_t> dOffsets(
			offsets.size() * sizeof(int32_t), "input boundary query offsets");
		cuflye::cuda_raii::DeviceBuffer<ChainInputRecord> dOutput(
			output.size() * sizeof(ChainInputRecord), "input boundary output");
		cuflye::cuda_raii::DeviceBuffer<DeviceStatus> dStatus(
			sizeof(DeviceStatus), "input boundary status");
		summary.deviceAllocationMs = elapsedMs(allocStart, Clock::now());

		auto h2dStart = Clock::now();
		cuflye::cuda_raii::checkCuda(
			cudaMemcpy(dRaw.get(), raw.data(), raw.size() * sizeof(RawOverlapRecord),
					   cudaMemcpyHostToDevice),
			"copy raw overlaps to device");
		cuflye::cuda_raii::checkCuda(
			cudaMemcpy(dOffsets.get(), offsets.data(),
					   offsets.size() * sizeof(int32_t),
					   cudaMemcpyHostToDevice),
			"copy query offsets to device");
		cuflye::cuda_raii::checkCuda(
			cudaMemcpy(dStatus.get(), &zeroStatus, sizeof(DeviceStatus),
					   cudaMemcpyHostToDevice),
			"initialize device status");
		summary.hostToDeviceMs = elapsedMs(h2dStart, Clock::now());

		auto kernelStart = Clock::now();
		int32_t threads = 128;
		int32_t blocks = static_cast<int32_t>((raw.size() + threads - 1) / threads);
		filterSortRawOverlapsKernel<<<blocks, threads>>>(
			dRaw.get(), static_cast<int32_t>(raw.size()), dOffsets.get(),
			dOutput.get(), dStatus.get());
		cuflye::cuda_raii::checkCuda(cudaGetLastError(),
									 "launch input boundary filter/sort kernel");
		cuflye::cuda_raii::checkCuda(cudaDeviceSynchronize(),
									 "synchronize input boundary kernel");
		summary.kernelMs = elapsedMs(kernelStart, Clock::now());

		auto d2hStart = Clock::now();
		DeviceStatus status{};
		cuflye::cuda_raii::checkCuda(
			cudaMemcpy(output.data(), dOutput.get(),
					   output.size() * sizeof(ChainInputRecord),
					   cudaMemcpyDeviceToHost),
			"copy input boundary output to host");
		cuflye::cuda_raii::checkCuda(
			cudaMemcpy(&status, dStatus.get(), sizeof(DeviceStatus),
					   cudaMemcpyDeviceToHost),
			"copy input boundary status to host");
		summary.deviceToHostMs = elapsedMs(d2hStart, Clock::now());
		if (status.errorCode != 0)
		{
			throw std::runtime_error("device filter/sort kernel reported an error");
		}
		if (status.outputRecords != static_cast<int32_t>(outputCount))
		{
			throw std::runtime_error("device output count mismatch");
		}

		auto writeStart = Clock::now();
		writeChainInputTsv(options.outputTsv, output);
		summary.writeMs = elapsedMs(writeStart, Clock::now());
		summary.totalMs = elapsedMs(totalStart, Clock::now());
		writeJson(options.jsonOutput, options, summary);
		return 0;
	}
	catch (const std::exception& exc)
	{
		std::cerr << "error: " << exc.what() << "\n";
		return 2;
	}
}
