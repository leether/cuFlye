// SPDX-License-Identifier: BSD-3-Clause

#include <cuda_runtime_api.h>

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>

namespace
{
struct Options
{
	int device = 0;
	bool hasMemoryBudget = false;
	unsigned long long memoryBudgetBytes = 0;
	std::string jsonOutput;
};

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
		default:
			if (static_cast<unsigned char>(ch) < 0x20)
			{
				out << "\\u";
				const char* hex = "0123456789abcdef";
				out << "00" << hex[(ch >> 4) & 0x0f] << hex[ch & 0x0f];
			}
			else
			{
				out << ch;
			}
		}
	}
	return out.str();
}

[[noreturn]] void usageError(const std::string& message)
{
	throw std::runtime_error(message +
		"\nUsage: cuflye-cuda-probe [--device N] [--memory-budget-bytes N] [--json-output PATH]");
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

		if (arg == "--device")
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
				<< "Usage: cuflye-cuda-probe [--device N] [--memory-budget-bytes N] "
				<< "[--json-output PATH]\n";
			std::exit(0);
		}
		else
		{
			usageError("Unknown option: " + arg);
		}
	}

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

std::string buildProbeJson(const Options& options)
{
	int runtimeVersion = 0;
	int driverVersion = 0;
	int deviceCount = 0;
	checkCuda(cudaRuntimeGetVersion(&runtimeVersion), "cudaRuntimeGetVersion failed");
	checkCuda(cudaDriverGetVersion(&driverVersion), "cudaDriverGetVersion failed");
	checkCuda(cudaGetDeviceCount(&deviceCount), "cudaGetDeviceCount failed");

	if (deviceCount <= 0)
	{
		throw std::runtime_error("CUDA runtime reported zero devices");
	}
	if (options.device < 0 || options.device >= deviceCount)
	{
		throw std::runtime_error("Requested CUDA device is outside available range");
	}

	checkCuda(cudaSetDevice(options.device), "cudaSetDevice failed");

	cudaDeviceProp prop;
	std::memset(&prop, 0, sizeof(prop));
	checkCuda(cudaGetDeviceProperties(&prop, options.device), "cudaGetDeviceProperties failed");

	size_t freeBytes = 0;
	size_t totalBytes = 0;
	checkCuda(cudaMemGetInfo(&freeBytes, &totalBytes), "cudaMemGetInfo failed");

	bool budgetSatisfied = true;
	if (options.hasMemoryBudget)
	{
		budgetSatisfied = freeBytes >= options.memoryBudgetBytes;
	}

	std::ostringstream json;
	json << "{\n";
	json << "  \"adapter\": \"cuda-runtime-probe-v0\",\n";
	json << "  \"status\": \"" << (budgetSatisfied ? "ok" : "insufficient_memory_budget") << "\",\n";
	json << "  \"device\": " << options.device << ",\n";
	json << "  \"device_count\": " << deviceCount << ",\n";
	json << "  \"device_name\": \"" << jsonEscape(prop.name) << "\",\n";
	json << "  \"compute_capability\": \"" << prop.major << "." << prop.minor << "\",\n";
	json << "  \"cuda_driver_version\": " << driverVersion << ",\n";
	json << "  \"cuda_runtime_version\": " << runtimeVersion << ",\n";
	json << "  \"global_memory_bytes\": " << static_cast<unsigned long long>(prop.totalGlobalMem) << ",\n";
	json << "  \"memory_free_bytes\": " << static_cast<unsigned long long>(freeBytes) << ",\n";
	json << "  \"memory_total_bytes\": " << static_cast<unsigned long long>(totalBytes) << ",\n";
	json << "  \"memory_budget_bytes\": ";
	if (options.hasMemoryBudget) json << options.memoryBudgetBytes;
	else json << "null";
	json << ",\n";
	json << "  \"memory_budget_satisfied\": " << (budgetSatisfied ? "true" : "false") << ",\n";
	json << "  \"multi_processor_count\": " << prop.multiProcessorCount << ",\n";
	json << "  \"warp_size\": " << prop.warpSize << ",\n";
	json << "  \"max_threads_per_block\": " << prop.maxThreadsPerBlock << ",\n";
	json << "  \"shared_memory_per_block_bytes\": "
		 << static_cast<unsigned long long>(prop.sharedMemPerBlock) << ",\n";
	json << "  \"registers_per_block\": " << prop.regsPerBlock << ",\n";
	json << "  \"memory_bus_width_bits\": " << prop.memoryBusWidth << "\n";
	json << "}\n";
	return json.str();
}
}

int main(int argc, char** argv)
{
	try
	{
		Options options = parseArgs(argc, argv);
		std::string output = buildProbeJson(options);

		if (!options.jsonOutput.empty())
		{
			std::ofstream handle(options.jsonOutput);
			if (!handle)
			{
				throw std::runtime_error("Can't open JSON output path: " + options.jsonOutput);
			}
			handle << output;
		}
		std::cout << output;

		return output.find("\"status\": \"ok\"") != std::string::npos ? 0 : 1;
	}
	catch (const std::exception& exc)
	{
		std::cerr << "cuFlye CUDA probe failed: " << exc.what() << "\n";
		return 1;
	}
}
