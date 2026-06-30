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
	std::string inputTsv;
	std::string outputTsv;
	std::string cpuSampleOutput;
	std::string jsonOutput;
	int device = 0;
	size_t records = 128;
	bool hasMemoryBudget = false;
	unsigned long long memoryBudgetBytes = 0;
};

__global__ void emitCandidateRecordsKernel(const CandidateRecord* input,
										   CandidateRecord* output,
										   size_t count)
{
	size_t index = static_cast<size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
	if (index < count)
	{
		output[index] = input[index];
	}
}

[[noreturn]] void usageError(const std::string& message)
{
	throw std::runtime_error(message +
		"\nUsage: cuflye-cuda-candidate-smoke --input-cpu-tsv PATH --output-tsv PATH "
		"[--cpu-sample-output PATH] [--records N] [--device N] "
		"[--memory-budget-bytes N] [--json-output PATH]");
}

unsigned long long parseUnsigned(const std::string& value, const std::string& name)
{
	if (value.empty()) usageError(name + " must not be empty");
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

		if (arg == "--input-cpu-tsv")
		{
			options.inputTsv = requireValue(arg);
		}
		else if (arg == "--output-tsv")
		{
			options.outputTsv = requireValue(arg);
		}
		else if (arg == "--cpu-sample-output")
		{
			options.cpuSampleOutput = requireValue(arg);
		}
		else if (arg == "--records")
		{
			options.records = static_cast<size_t>(parseUnsigned(requireValue(arg), arg));
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
				<< "Usage: cuflye-cuda-candidate-smoke --input-cpu-tsv PATH "
				<< "--output-tsv PATH [--cpu-sample-output PATH] [--records N] "
				<< "[--device N] [--memory-budget-bytes N] [--json-output PATH]\n";
			std::exit(0);
		}
		else
		{
			usageError("Unknown option: " + arg);
		}
	}

	if (options.inputTsv.empty()) usageError("--input-cpu-tsv is required");
	if (options.outputTsv.empty()) usageError("--output-tsv is required");
	if (options.records == 0) usageError("--records must be greater than zero");
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

uint64_t parseUint64Field(const std::string& value, const std::string& fieldName)
{
	return parseUnsigned(value, fieldName);
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

CandidateRecord parseCandidateLine(std::string line, size_t lineNumber)
{
	if (!line.empty() && line.back() == '\r') line.pop_back();
	std::vector<std::string> fields = splitTabs(line);
	if (fields.size() != 6)
	{
		throw std::runtime_error("line " + std::to_string(lineNumber) +
								 ": expected 6 candidate fields");
	}
	if (fields[5] != "+" && fields[5] != "-")
	{
		throw std::runtime_error("line " + std::to_string(lineNumber) +
								 ": target_strand must be '+' or '-'");
	}

	CandidateRecord record;
	std::memset(&record, 0, sizeof(record));
	record.queryId = parseInt64Field(fields[0], "query_id");
	record.queryPos = parseUint64Field(fields[1], "query_pos");
	record.kmer = parseUint64Field(fields[2], "kmer");
	record.targetId = parseInt64Field(fields[3], "target_id");
	record.targetPos = parseUint64Field(fields[4], "target_pos");
	record.targetStrand = fields[5][0];
	return record;
}

std::vector<CandidateRecord> readCpuSample(const std::string& path, size_t count)
{
	std::ifstream input(path);
	if (!input)
	{
		throw std::runtime_error("Can't open CPU candidate TSV: " + path);
	}

	std::vector<CandidateRecord> records;
	records.reserve(count);
	std::string line;
	size_t lineNumber = 0;
	while (records.size() < count && std::getline(input, line))
	{
		++lineNumber;
		if (line.empty()) throw std::runtime_error("blank candidate record at line " + std::to_string(lineNumber));
		records.push_back(parseCandidateLine(line, lineNumber));
	}

	if (records.size() != count)
	{
		throw std::runtime_error("CPU candidate TSV ended before requested record count");
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
					  size_t requiredBytes)
{
	std::ostringstream json;
	json << "{\n";
	json << "  \"adapter\": \"cuda-candidate-smoke-v0\",\n";
	json << "  \"status\": \"ok\",\n";
	json << "  \"abi\": \"candidate-record-v1\",\n";
	json << "  \"device\": " << options.device << ",\n";
	json << "  \"device_name\": \"" << jsonEscape(prop.name) << "\",\n";
	json << "  \"compute_capability\": \"" << prop.major << "." << prop.minor << "\",\n";
	json << "  \"records\": " << options.records << ",\n";
	json << "  \"record_size_bytes\": " << sizeof(CandidateRecord) << ",\n";
	json << "  \"device_allocation_bytes\": " << requiredBytes << ",\n";
	json << "  \"memory_free_bytes\": " << static_cast<unsigned long long>(freeBytes) << ",\n";
	json << "  \"memory_total_bytes\": " << static_cast<unsigned long long>(totalBytes) << ",\n";
	json << "  \"memory_budget_bytes\": ";
	if (options.hasMemoryBudget) json << options.memoryBudgetBytes;
	else json << "null";
	json << ",\n";
	json << "  \"memory_budget_satisfied\": true,\n";
	json << "  \"input_cpu_tsv\": \"" << jsonEscape(options.inputTsv) << "\",\n";
	json << "  \"cpu_sample_output\": \"" << jsonEscape(options.cpuSampleOutput) << "\",\n";
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
}

int main(int argc, char** argv)
{
	try
	{
		Options options = parseArgs(argc, argv);

		checkCuda(cudaSetDevice(options.device), "cudaSetDevice failed");
		cudaDeviceProp prop;
		std::memset(&prop, 0, sizeof(prop));
		checkCuda(cudaGetDeviceProperties(&prop, options.device), "cudaGetDeviceProperties failed");

		size_t freeBytes = 0;
		size_t totalBytes = 0;
		checkCuda(cudaMemGetInfo(&freeBytes, &totalBytes), "cudaMemGetInfo failed");

		std::vector<CandidateRecord> cpuRecords = readCpuSample(options.inputTsv, options.records);
		writeCandidateTsv(options.cpuSampleOutput, cpuRecords);

		size_t recordBytes = options.records * sizeof(CandidateRecord);
		size_t requiredBytes = recordBytes * 2;
		if (options.hasMemoryBudget && requiredBytes > options.memoryBudgetBytes)
		{
			throw std::runtime_error("CUDA candidate smoke memory budget is smaller than required device allocation");
		}
		if (requiredBytes > freeBytes)
		{
			throw std::runtime_error("CUDA candidate smoke required device allocation exceeds free device memory");
		}

		cuflye::cuda_raii::DeviceBuffer<CandidateRecord> deviceInput(recordBytes, "input");
		cuflye::cuda_raii::DeviceBuffer<CandidateRecord> deviceOutput(recordBytes, "output");
		checkCuda(cudaMemcpy(deviceInput.get(), cpuRecords.data(), recordBytes, cudaMemcpyHostToDevice),
				  "cudaMemcpy host-to-device failed");

		const int threadsPerBlock = 128;
		const int blocks = static_cast<int>((options.records + threadsPerBlock - 1) / threadsPerBlock);
		emitCandidateRecordsKernel<<<blocks, threadsPerBlock>>>(
			deviceInput.get(),
			deviceOutput.get(),
			options.records);
		checkCuda(cudaGetLastError(), "emitCandidateRecordsKernel launch failed");
		checkCuda(cudaDeviceSynchronize(), "emitCandidateRecordsKernel execution failed");

		std::vector<CandidateRecord> gpuRecords(options.records);
		checkCuda(cudaMemcpy(gpuRecords.data(), deviceOutput.get(), recordBytes, cudaMemcpyDeviceToHost),
				  "cudaMemcpy device-to-host failed");

		writeCandidateTsv(options.outputTsv, gpuRecords);
		std::string json = buildJson(options, prop, freeBytes, totalBytes, requiredBytes);
		writeText(options.jsonOutput, json);
		std::cout << json;
		return 0;
	}
	catch (const std::exception& exc)
	{
		std::cerr << "cuFlye CUDA candidate smoke failed: " << exc.what() << "\n";
		return 1;
	}
}
