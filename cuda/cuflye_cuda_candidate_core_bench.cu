// SPDX-License-Identifier: BSD-3-Clause

#include <cuda_runtime_api.h>

#include <algorithm>
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
struct Options
{
	size_t queries = 8192;
	size_t indexEntries = 32768;
	uint64_t keySpace = 4096;
	int trials = 5;
	int warmupTrials = 1;
	int device = 0;
	int threadsPerBlock = 256;
	int blocks = 0;
	std::string jsonOutput;
};

__global__ void countMatchesKernel(const uint64_t* queries,
								   size_t queryCount,
								   const uint64_t* targets,
								   size_t targetCount,
								   uint64_t pairCount,
								   uint64_t* blockCounts)
{
	extern __shared__ uint64_t sharedCounts[];
	uint32_t tid = threadIdx.x;
	uint64_t localCount = 0;
	uint64_t stride = static_cast<uint64_t>(gridDim.x) * blockDim.x;
	for (uint64_t pairIndex = static_cast<uint64_t>(blockIdx.x) * blockDim.x + tid;
		 pairIndex < pairCount;
		 pairIndex += stride)
	{
		size_t queryIndex = static_cast<size_t>(pairIndex / targetCount);
		size_t targetIndex = static_cast<size_t>(pairIndex % targetCount);
		if (queries[queryIndex] == targets[targetIndex]) ++localCount;
	}

	sharedCounts[tid] = localCount;
	__syncthreads();
	for (uint32_t offset = blockDim.x / 2; offset > 0; offset >>= 1)
	{
		if (tid < offset)
		{
			sharedCounts[tid] += sharedCounts[tid + offset];
		}
		__syncthreads();
	}
	if (tid == 0) blockCounts[blockIdx.x] = sharedCounts[0];
}

[[noreturn]] void usageError(const std::string& message)
{
	throw std::runtime_error(message +
		"\nUsage: cuflye-cuda-candidate-core-bench [--queries N] "
		"[--index-entries N] [--key-space N] [--trials N] [--warmup-trials N] "
		"[--device N] [--threads-per-block N] [--blocks N] [--json-output PATH]");
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

	for (int index = 1; index < argc; ++index)
	{
		std::string arg = argv[index];
		auto requireValue = [&](const std::string& name) -> std::string
		{
			if (index + 1 >= argc) usageError(name + " requires a value");
			return argv[++index];
		};

		if (arg == "--queries")
		{
			options.queries = static_cast<size_t>(parseUnsigned(requireValue(arg), arg));
		}
		else if (arg == "--index-entries")
		{
			options.indexEntries = static_cast<size_t>(parseUnsigned(requireValue(arg), arg));
		}
		else if (arg == "--key-space")
		{
			options.keySpace = parseUnsigned(requireValue(arg), arg);
		}
		else if (arg == "--trials")
		{
			options.trials = parseInt(requireValue(arg), arg);
		}
		else if (arg == "--warmup-trials")
		{
			options.warmupTrials = parseInt(requireValue(arg), arg);
		}
		else if (arg == "--device")
		{
			options.device = parseInt(requireValue(arg), arg);
		}
		else if (arg == "--threads-per-block")
		{
			options.threadsPerBlock = parseInt(requireValue(arg), arg);
		}
		else if (arg == "--blocks")
		{
			options.blocks = parseInt(requireValue(arg), arg);
		}
		else if (arg == "--json-output")
		{
			options.jsonOutput = requireValue(arg);
		}
		else if (arg == "-h" || arg == "--help")
		{
			std::cout
				<< "Usage: cuflye-cuda-candidate-core-bench [--queries N] "
				<< "[--index-entries N] [--key-space N] [--trials N] "
				<< "[--warmup-trials N] [--device N] [--threads-per-block N] "
				<< "[--blocks N] [--json-output PATH]\n";
			std::exit(0);
		}
		else
		{
			usageError("Unknown option: " + arg);
		}
	}

	if (options.queries == 0) usageError("--queries must be greater than zero");
	if (options.indexEntries == 0) usageError("--index-entries must be greater than zero");
	if (options.keySpace == 0) usageError("--key-space must be greater than zero");
	if (options.trials <= 0) usageError("--trials must be greater than zero");
	if (options.warmupTrials < 0) usageError("--warmup-trials must not be negative");
	if (options.threadsPerBlock <= 0) usageError("--threads-per-block must be greater than zero");
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

size_t checkedMultiply(size_t left, size_t right, const std::string& name)
{
	if (right != 0 && left > std::numeric_limits<size_t>::max() / right)
	{
		throw std::runtime_error(name + " size overflow");
	}
	return left * right;
}

std::vector<uint64_t> makeKeys(size_t count, uint64_t keySpace, uint64_t salt)
{
	std::vector<uint64_t> keys;
	keys.reserve(count);
	for (size_t index = 0; index < count; ++index)
	{
		keys.push_back((static_cast<uint64_t>(index) * 1315423911ULL + salt) % keySpace);
	}
	return keys;
}

uint64_t countCpuMatches(const std::vector<uint64_t>& queries,
						 const std::vector<uint64_t>& targets)
{
	uint64_t matches = 0;
	for (uint64_t query : queries)
	{
		for (uint64_t target : targets)
		{
			if (query == target) ++matches;
		}
	}
	return matches;
}

double elapsedMs(std::chrono::steady_clock::time_point start,
				 std::chrono::steady_clock::time_point stop)
{
	return std::chrono::duration<double, std::milli>(stop - start).count();
}

double minValue(const std::vector<double>& values)
{
	return *std::min_element(values.begin(), values.end());
}

double avgValue(const std::vector<double>& values)
{
	double total = 0.0;
	for (double value : values) total += value;
	return total / values.size();
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
		size_t pairCountSize = checkedMultiply(options.queries, options.indexEntries,
											   "query/index pair");
		uint64_t pairCount = static_cast<uint64_t>(pairCountSize);
		std::vector<uint64_t> queryKeys = makeKeys(options.queries, options.keySpace, 17);
		std::vector<uint64_t> targetKeys = makeKeys(options.indexEntries, options.keySpace, 17);

		std::vector<double> cpuMs;
		uint64_t cpuMatches = 0;
		for (int trial = 0; trial < options.trials; ++trial)
		{
			auto start = std::chrono::steady_clock::now();
			uint64_t matches = countCpuMatches(queryKeys, targetKeys);
			auto stop = std::chrono::steady_clock::now();
			if (trial == 0) cpuMatches = matches;
			if (matches != cpuMatches) throw std::runtime_error("CPU match count changed across trials");
			cpuMs.push_back(elapsedMs(start, stop));
		}

		checkCuda(cudaSetDevice(options.device), "cudaSetDevice failed");
		cudaDeviceProp prop;
		std::memset(&prop, 0, sizeof(prop));
		checkCuda(cudaGetDeviceProperties(&prop, options.device), "cudaGetDeviceProperties failed");

		int blocks = options.blocks;
		if (blocks == 0)
		{
			uint64_t suggested = (pairCount + options.threadsPerBlock - 1) /
								 static_cast<uint64_t>(options.threadsPerBlock);
			blocks = static_cast<int>(std::min<uint64_t>(65535, suggested));
		}
		if (blocks <= 0) usageError("--blocks must be greater than zero");

		uint64_t* deviceQueries = nullptr;
		uint64_t* deviceTargets = nullptr;
		uint64_t* deviceBlockCounts = nullptr;
		size_t queryBytes = checkedMultiply(queryKeys.size(), sizeof(uint64_t), "query buffer");
		size_t targetBytes = checkedMultiply(targetKeys.size(), sizeof(uint64_t), "target buffer");
		size_t blockCountBytes = checkedMultiply(static_cast<size_t>(blocks), sizeof(uint64_t),
												 "block count buffer");
		checkCuda(cudaMalloc(&deviceQueries, queryBytes), "cudaMalloc queries failed");
		checkCuda(cudaMalloc(&deviceTargets, targetBytes), "cudaMalloc targets failed");
		checkCuda(cudaMalloc(&deviceBlockCounts, blockCountBytes), "cudaMalloc block counts failed");
		checkCuda(cudaMemcpy(deviceQueries, queryKeys.data(), queryBytes, cudaMemcpyHostToDevice),
				  "cudaMemcpy queries host-to-device failed");
		checkCuda(cudaMemcpy(deviceTargets, targetKeys.data(), targetBytes, cudaMemcpyHostToDevice),
				  "cudaMemcpy targets host-to-device failed");

		cudaEvent_t startEvent = nullptr;
		cudaEvent_t stopEvent = nullptr;
		checkCuda(cudaEventCreate(&startEvent), "cudaEventCreate start failed");
		checkCuda(cudaEventCreate(&stopEvent), "cudaEventCreate stop failed");

		std::vector<uint64_t> blockCounts(static_cast<size_t>(blocks), 0);
		std::vector<double> gpuKernelMs;
		std::vector<double> gpuTotalMs;
		uint64_t gpuMatches = 0;
		int totalGpuTrials = options.warmupTrials + options.trials;
		for (int trial = 0; trial < totalGpuTrials; ++trial)
		{
			auto totalStart = std::chrono::steady_clock::now();
			checkCuda(cudaMemset(deviceBlockCounts, 0, blockCountBytes),
					  "cudaMemset block counts failed");
			checkCuda(cudaEventRecord(startEvent), "cudaEventRecord start failed");
			countMatchesKernel<<<blocks, options.threadsPerBlock,
								 static_cast<size_t>(options.threadsPerBlock) * sizeof(uint64_t)>>>(
				deviceQueries,
				queryKeys.size(),
				deviceTargets,
				targetKeys.size(),
				pairCount,
				deviceBlockCounts);
			checkCuda(cudaGetLastError(), "countMatchesKernel launch failed");
			checkCuda(cudaEventRecord(stopEvent), "cudaEventRecord stop failed");
			checkCuda(cudaEventSynchronize(stopEvent), "cudaEventSynchronize stop failed");
			float kernelMs = 0.0f;
			checkCuda(cudaEventElapsedTime(&kernelMs, startEvent, stopEvent),
					  "cudaEventElapsedTime failed");
			checkCuda(cudaMemcpy(blockCounts.data(), deviceBlockCounts, blockCountBytes,
								 cudaMemcpyDeviceToHost),
					  "cudaMemcpy block counts device-to-host failed");
			auto totalStop = std::chrono::steady_clock::now();
			uint64_t matches = 0;
			for (uint64_t blockCount : blockCounts) matches += blockCount;
			if (matches != cpuMatches)
			{
				throw std::runtime_error("GPU match count does not match CPU match count");
			}
			gpuMatches = matches;
			if (trial >= options.warmupTrials)
			{
				gpuKernelMs.push_back(kernelMs);
				gpuTotalMs.push_back(elapsedMs(totalStart, totalStop));
			}
		}

		checkCuda(cudaEventDestroy(startEvent), "cudaEventDestroy start failed");
		checkCuda(cudaEventDestroy(stopEvent), "cudaEventDestroy stop failed");
		checkCuda(cudaFree(deviceQueries), "cudaFree queries failed");
		checkCuda(cudaFree(deviceTargets), "cudaFree targets failed");
		checkCuda(cudaFree(deviceBlockCounts), "cudaFree block counts failed");

		double cpuBest = minValue(cpuMs);
		double cpuAvg = avgValue(cpuMs);
		double gpuKernelBest = minValue(gpuKernelMs);
		double gpuKernelAvg = avgValue(gpuKernelMs);
		double gpuTotalBest = minValue(gpuTotalMs);
		double gpuTotalAvg = avgValue(gpuTotalMs);
		double kernelSpeedup = cpuBest / gpuKernelBest;
		double totalSpeedup = cpuBest / gpuTotalBest;

		std::ostringstream json;
		json << std::fixed << std::setprecision(6);
		json << "{\n";
		json << "  \"adapter\": \"cuda-candidate-core-bench-v0\",\n";
		json << "  \"status\": \"ok\",\n";
		json << "  \"device\": " << options.device << ",\n";
		json << "  \"device_name\": \"" << jsonEscape(prop.name) << "\",\n";
		json << "  \"compute_capability\": \"" << prop.major << "." << prop.minor << "\",\n";
		json << "  \"queries\": " << options.queries << ",\n";
		json << "  \"index_entries\": " << options.indexEntries << ",\n";
		json << "  \"pair_count\": " << pairCount << ",\n";
		json << "  \"key_space\": " << options.keySpace << ",\n";
		json << "  \"trials\": " << options.trials << ",\n";
		json << "  \"warmup_trials\": " << options.warmupTrials << ",\n";
		json << "  \"threads_per_block\": " << options.threadsPerBlock << ",\n";
		json << "  \"blocks\": " << blocks << ",\n";
		json << "  \"cpu_matches\": " << cpuMatches << ",\n";
		json << "  \"gpu_matches\": " << gpuMatches << ",\n";
		json << "  \"counts_match\": true,\n";
		json << "  \"cpu_ms_best\": " << cpuBest << ",\n";
		json << "  \"cpu_ms_avg\": " << cpuAvg << ",\n";
		json << "  \"gpu_kernel_ms_best\": " << gpuKernelBest << ",\n";
		json << "  \"gpu_kernel_ms_avg\": " << gpuKernelAvg << ",\n";
		json << "  \"gpu_total_ms_best\": " << gpuTotalBest << ",\n";
		json << "  \"gpu_total_ms_avg\": " << gpuTotalAvg << ",\n";
		json << "  \"speedup_cpu_vs_gpu_kernel_best\": " << kernelSpeedup << ",\n";
		json << "  \"speedup_cpu_vs_gpu_total_best\": " << totalSpeedup << ",\n";
		json << "  \"candidate_core_gpu_faster_than_cpu\": "
			 << (totalSpeedup > 1.0 ? "true" : "false") << "\n";
		json << "}\n";
		writeText(options.jsonOutput, json.str());
		std::cout << json.str();
		return totalSpeedup > 1.0 ? 0 : 2;
	}
	catch (const std::exception& exc)
	{
		std::cerr << "cuFlye CUDA candidate core benchmark failed: " << exc.what() << "\n";
		return 1;
	}
}
