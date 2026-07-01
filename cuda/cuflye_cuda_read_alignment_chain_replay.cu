// SPDX-License-Identifier: BSD-3-Clause

#include <cuda_runtime_api.h>

#include "cuflye_cuda_raii.hpp"

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

namespace
{
using Clock = std::chrono::steady_clock;
static const size_t MAX_REPLAY_RECORDS = 2048;

struct EdgeOverlap
{
	int64_t candidateId;
	int64_t readId;
	int32_t readBegin;
	int32_t readEnd;
	int32_t readLen;
	int64_t edgeId;
	int32_t edgeLeftNode;
	int32_t edgeRightNode;
	int64_t edgeSeqId;
	int32_t edgeBegin;
	int32_t edgeEnd;
	int32_t edgeLen;
	int32_t score;
	float seqDivergence;
};

struct ReplayParams
{
	int32_t maximumJump;
	int32_t maxReadOverlap;
	int32_t minimumOverlap;
	int32_t maxSeparation;
};

struct ChainRecord
{
	int32_t parent;
	int32_t overlapIndex;
	int32_t firstIndex;
	int32_t lastIndex;
	int32_t length;
	int32_t score;
};

struct OutputSegment
{
	int32_t chainId;
	int32_t segmentId;
	int32_t overlapIndex;
};

struct DeviceSummary
{
	int32_t valid;
	int32_t errorCode;
	int32_t candidateChains;
	int32_t preDivergenceAcceptedChains;
	int32_t acceptedChains;
	int32_t outputRecords;
};

struct FixtureManifest
{
	int64_t queryId = 0;
	int32_t alignmentInputRecords = 0;
	int32_t candidateChains = 0;
	int32_t oracleChains = 0;
	ReplayParams params{};
	bool readsBaseAlignment = false;
};

struct LoadedFixture
{
	std::string fixtureDir;
	FixtureManifest manifest;
	std::vector<EdgeOverlap> overlaps;
	std::vector<uint8_t> divergenceAccepted;
};

struct Options
{
	std::string fixtureDir;
	std::string outputTsv;
	std::string jsonOutput;
	std::string batchFixturesFile;
	std::string batchOutputDir;
	std::string batchJsonOutput;
	std::string workerRequestJson;
	std::string workerRequestsJsonl;
	std::string workerSessionDir;
	std::string backend = "cuda";
	int device = 0;
	uint32_t warmupRuns = 0;
	uint32_t benchmarkRuns = 1;
	uint32_t replicateFixture = 1;
	uint32_t workerSessionMaxRequests = 1;
	uint32_t workerSessionPollMs = 2;
	uint32_t workerSessionTimeoutMs = 600000;
	bool hasMemoryBudget = false;
	unsigned long long memoryBudgetBytes = 0;
	bool allowHeterogeneousBatch = false;
	bool cudaPersistentArena = false;
	bool cudaPersistentBulkOutput = false;
	bool emitPreDivergenceChains = false;
};

struct RunSummary
{
	std::string backend;
	std::string cudaExecutionMode;
	double setupMs = 0.0;
	double deviceAllocationMs = 0.0;
	double hostToDeviceMs = 0.0;
	double kernelMs = 0.0;
	double cpuChainMs = 0.0;
	double deviceToHostMs = 0.0;
	double finalizeMs = 0.0;
	double oneTimeSetupMs = 0.0;
	double oneTimeDeviceAllocationMs = 0.0;
	double oneTimeHostToDeviceMs = 0.0;
	double oneTimeTotalMs = 0.0;
	double writeMs = 0.0;
	double totalBeforeJsonMs = 0.0;
	double benchmarkMeanTotalMs = 0.0;
	double benchmarkMinTotalMs = 0.0;
	double benchmarkMaxTotalMs = 0.0;
	double benchmarkMeanCoreMs = 0.0;
	uint32_t warmupRuns = 0;
	uint32_t timedRuns = 0;
	size_t batchSize = 1;
	size_t inputRecords = 0;
	size_t minInputRecords = 0;
	size_t maxInputRecords = 0;
	size_t totalInputRecords = 0;
	size_t shapeGroups = 1;
	size_t candidateChains = 0;
	size_t preDivergenceAcceptedChains = 0;
	size_t acceptedChains = 0;
	size_t outputRecords = 0;
	size_t requiredBytes = 0;
	size_t freeBytes = 0;
	size_t totalBytes = 0;
	std::string deviceName;
	int device = 0;
};

struct ReadAlignmentWorkerRequest
{
	std::string schema;
	std::string requestId;
	std::string responseJson;
	std::string adapterMode;
	std::string readAlignmentAbi;
	std::string outputMode;
	std::string cudaExecutionMode;
	Options options;
	bool hasExpectedFixtureCount = false;
	size_t expectedFixtureCount = 0;
};

struct BatchFixtureOutput
{
	std::string fixtureDir;
	std::string outputTsv;
	int64_t queryId = 0;
	size_t inputRecords = 0;
	size_t chainDivergenceRows = 0;
	size_t outputRecords = 0;
	ReplayParams params{};
};

struct BatchShapeOutputSummary
{
	size_t inputRecords = 0;
	size_t chainDivergenceRows = 0;
	ReplayParams params{};
	size_t fixtureCount = 0;
	size_t totalInputRecords = 0;
	size_t outputRecords = 0;
	std::vector<int64_t> queryIds;
};

struct CudaGroupArena
{
	std::vector<size_t> originalIndices;
	ReplayParams params{};
	size_t overlapCount = 0;
	size_t divergenceCount = 0;
	size_t outputCapacity = 0;
	size_t batchSize = 0;
	size_t requiredBytes = 0;
	cuflye::cuda_raii::DeviceBuffer<EdgeOverlap> dOverlaps;
	cuflye::cuda_raii::DeviceBuffer<uint8_t> dDivergence;
	cuflye::cuda_raii::DeviceBuffer<ChainRecord> dChains;
	cuflye::cuda_raii::DeviceBuffer<int32_t> dActive;
	cuflye::cuda_raii::DeviceBuffer<int32_t> dFrozen;
	cuflye::cuda_raii::DeviceBuffer<int32_t> dOrdered;
	cuflye::cuda_raii::DeviceBuffer<int32_t> dAccepted;
	cuflye::cuda_raii::DeviceBuffer<int32_t> dScratch;
	cuflye::cuda_raii::DeviceBuffer<OutputSegment> dOutput;
	cuflye::cuda_raii::DeviceBuffer<DeviceSummary> dSummary;
};

struct CudaPersistentArena
{
	std::vector<CudaGroupArena> groups;
	double setupMs = 0.0;
	double deviceAllocationMs = 0.0;
	double hostToDeviceMs = 0.0;
	size_t requiredBytes = 0;
	size_t totalInputRecords = 0;
	size_t minInputRecords = 0;
	size_t maxInputRecords = 0;
	size_t fixtureCount = 0;
	size_t freeBytes = 0;
	size_t totalBytes = 0;
	std::string deviceName;
	int device = 0;
};

struct ReadAlignmentSessionCache
{
	bool initialized = false;
	std::string batchFixturesFile;
	int device = 0;
	bool hasMemoryBudget = false;
	unsigned long long memoryBudgetBytes = 0;
	bool emitPreDivergenceChains = false;
	bool allowHeterogeneousBatch = false;
	std::vector<LoadedFixture> fixtures;
	CudaPersistentArena arena;
};

struct ReadAlignmentWorkerResult
{
	RunSummary summary;
	bool arenaCacheHit = false;
	bool arenaCacheCreated = false;
	size_t fixtureCount = 0;
	size_t outputRecords = 0;
};

struct CpuChain
{
	std::vector<int32_t> indices;
	int32_t score = 0;
};

void attachBenchmarkStats(RunSummary& summary, const std::vector<RunSummary>& timedRuns,
                          uint32_t warmupRuns);
RunSummary runCudaPersistentArenaBenchmarkWithExistingArena(
    const Options& options, const CudaPersistentArena& arenaContext,
    std::vector<std::vector<OutputSegment>>& segmentsByFixture);

double elapsedMs(Clock::time_point start, Clock::time_point end)
{
	return std::chrono::duration<double, std::milli>(end - start).count();
}

std::string joinPath(const std::string& root, const std::string& leaf)
{
	if (root.empty()) return leaf;
	if (root[root.size() - 1] == '/') return root + leaf;
	return root + "/" + leaf;
}

std::string baseName(const std::string& path)
{
	size_t end = path.find_last_not_of('/');
	if (end == std::string::npos) return path;
	size_t begin = path.find_last_of('/', end);
	if (begin == std::string::npos) return path.substr(0, end + 1);
	return path.substr(begin + 1, end - begin);
}

std::string jsonEscape(const std::string& text)
{
	std::ostringstream escaped;
	for (char ch : text)
	{
		switch (ch)
		{
		case '\\':
			escaped << "\\\\";
			break;
		case '"':
			escaped << "\\\"";
			break;
		case '\n':
			escaped << "\\n";
			break;
		case '\r':
			escaped << "\\r";
			break;
		case '\t':
			escaped << "\\t";
			break;
		default:
			escaped << ch;
			break;
		}
	}
	return escaped.str();
}

void ensureDirectory(const std::string& path)
{
	if (path.empty()) return;
	std::string current;
	size_t index = 0;
	if (path[0] == '/')
	{
		current = "/";
		index = 1;
	}
	while (index <= path.size())
	{
		size_t slash = path.find('/', index);
		std::string part =
		    path.substr(index, slash == std::string::npos ? std::string::npos : slash - index);
		if (!part.empty())
		{
			if (!current.empty() && current[current.size() - 1] != '/') current += "/";
			current += part;
			if (::mkdir(current.c_str(), 0775) != 0 && errno != EEXIST)
			{
				throw std::runtime_error("cannot create directory: " + current + ": " +
				                         std::strerror(errno));
			}
		}
		if (slash == std::string::npos) break;
		index = slash + 1;
	}
}

void ensureParentDirectory(const std::string& path)
{
	size_t slash = path.find_last_of('/');
	if (slash == std::string::npos || slash == 0) return;
	ensureDirectory(path.substr(0, slash));
}

std::string readTextFile(const std::string& path)
{
	std::ifstream input(path);
	if (!input)
	{
		throw std::runtime_error("cannot read file: " + path);
	}
	std::ostringstream buffer;
	buffer << input.rdbuf();
	return buffer.str();
}

void writeTextFile(const std::string& path, const std::string& text)
{
	ensureParentDirectory(path);
	std::ofstream output(path);
	if (!output)
	{
		throw std::runtime_error("cannot write file: " + path);
	}
	output << text;
}

std::string trim(const std::string& text)
{
	size_t begin = 0;
	while (begin < text.size() &&
	       std::isspace(static_cast<unsigned char>(text[begin])))
	{
		++begin;
	}
	size_t end = text.size();
	while (end > begin && std::isspace(static_cast<unsigned char>(text[end - 1])))
	{
		--end;
	}
	return text.substr(begin, end - begin);
}

void skipJsonWhitespace(const std::string& text, size_t& offset)
{
	while (offset < text.size() &&
	       std::isspace(static_cast<unsigned char>(text[offset])))
	{
		++offset;
	}
}

std::string parseJsonStringToken(const std::string& text, size_t& offset)
{
	skipJsonWhitespace(text, offset);
	if (offset >= text.size() || text[offset] != '"')
	{
		throw std::runtime_error("JSON string expected");
	}
	++offset;
	std::ostringstream value;
	while (offset < text.size())
	{
		char ch = text[offset++];
		if (ch == '"') return value.str();
		if (ch != '\\')
		{
			value << ch;
			continue;
		}
		if (offset >= text.size()) throw std::runtime_error("unterminated JSON escape");
		char escaped = text[offset++];
		switch (escaped)
		{
		case '"': value << '"'; break;
		case '\\': value << '\\'; break;
		case '/': value << '/'; break;
		case 'b': value << '\b'; break;
		case 'f': value << '\f'; break;
		case 'n': value << '\n'; break;
		case 'r': value << '\r'; break;
		case 't': value << '\t'; break;
		default:
			throw std::runtime_error("unsupported JSON escape sequence");
		}
	}
	throw std::runtime_error("unterminated JSON string");
}

std::string parseJsonValueToken(const std::string& text, size_t& offset)
{
	skipJsonWhitespace(text, offset);
	if (offset >= text.size()) throw std::runtime_error("JSON value expected");
	if (text[offset] == '"') return parseJsonStringToken(text, offset);
	if (text[offset] == '{' || text[offset] == '[')
	{
		throw std::runtime_error(
		    "nested JSON values are not supported by read-alignment worker v0");
	}
	size_t begin = offset;
	while (offset < text.size() && text[offset] != ',' && text[offset] != '}') ++offset;
	std::string value = trim(text.substr(begin, offset - begin));
	if (value.empty()) throw std::runtime_error("JSON scalar value expected");
	return value;
}

std::map<std::string, std::string> parseFlatJsonObject(const std::string& text)
{
	std::map<std::string, std::string> fields;
	size_t offset = 0;
	skipJsonWhitespace(text, offset);
	if (offset >= text.size() || text[offset] != '{')
	{
		throw std::runtime_error("JSON object expected");
	}
	++offset;
	while (true)
	{
		skipJsonWhitespace(text, offset);
		if (offset < text.size() && text[offset] == '}')
		{
			++offset;
			break;
		}
		std::string key = parseJsonStringToken(text, offset);
		skipJsonWhitespace(text, offset);
		if (offset >= text.size() || text[offset] != ':')
		{
			throw std::runtime_error("JSON object field separator ':' expected");
		}
		++offset;
		std::string value = parseJsonValueToken(text, offset);
		if (!fields.insert(std::make_pair(key, value)).second)
		{
			throw std::runtime_error("duplicate JSON field: " + key);
		}
		skipJsonWhitespace(text, offset);
		if (offset < text.size() && text[offset] == ',')
		{
			++offset;
			continue;
		}
		if (offset < text.size() && text[offset] == '}')
		{
			++offset;
			break;
		}
		throw std::runtime_error("JSON object field separator ',' or '}' expected");
	}
	skipJsonWhitespace(text, offset);
	if (offset != text.size()) throw std::runtime_error("unexpected characters after JSON object");
	return fields;
}

std::string requireJsonField(const std::map<std::string, std::string>& fields,
                             const std::string& key)
{
	auto iter = fields.find(key);
	if (iter == fields.end() || iter->second.empty())
	{
		throw std::runtime_error("read-alignment worker request missing required field: " + key);
	}
	return iter->second;
}

std::string optionalJsonField(const std::map<std::string, std::string>& fields,
                              const std::string& key)
{
	auto iter = fields.find(key);
	if (iter == fields.end()) return "";
	return iter->second;
}

unsigned long long parseWorkerUnsigned(const std::string& value,
                                       const std::string& name)
{
	if (value.empty()) throw std::runtime_error(name + " must not be empty");
	if (value[0] == '-') throw std::runtime_error(name + " must be unsigned: " + value);
	char* end = nullptr;
	errno = 0;
	unsigned long long parsed = std::strtoull(value.c_str(), &end, 10);
	if (errno != 0 || end == value.c_str() || *end != '\0')
	{
		throw std::runtime_error(name + " must be an unsigned decimal integer: " + value);
	}
	return parsed;
}

int parseWorkerInt(const std::string& value, const std::string& name)
{
	unsigned long long parsed = parseWorkerUnsigned(value, name);
	if (parsed > static_cast<unsigned long long>(std::numeric_limits<int>::max()))
	{
		throw std::runtime_error(name + " is outside int range: " + value);
	}
	return static_cast<int>(parsed);
}

uint32_t parseWorkerUInt32(const std::string& value, const std::string& name)
{
	unsigned long long parsed = parseWorkerUnsigned(value, name);
	if (parsed > static_cast<unsigned long long>(std::numeric_limits<uint32_t>::max()))
	{
		throw std::runtime_error(name + " is outside uint32 range: " + value);
	}
	return static_cast<uint32_t>(parsed);
}

bool parseWorkerBool(const std::string& value, const std::string& name)
{
	if (value == "true") return true;
	if (value == "false") return false;
	throw std::runtime_error(name + " must be true or false: " + value);
}

std::vector<std::string> splitTabs(const std::string& line)
{
	std::vector<std::string> fields;
	std::string field;
	std::stringstream stream(line);
	while (std::getline(stream, field, '\t'))
		fields.push_back(field);
	return fields;
}

size_t findJsonValue(const std::string& text, const std::string& key)
{
	std::string pattern = "\"" + key + "\"";
	size_t keyPos = text.find(pattern);
	if (keyPos == std::string::npos)
	{
		throw std::runtime_error("manifest missing key: " + key);
	}
	size_t colon = text.find(':', keyPos + pattern.size());
	if (colon == std::string::npos)
	{
		throw std::runtime_error("manifest malformed near key: " + key);
	}
	size_t value = colon + 1;
	while (value < text.size() && std::isspace(static_cast<unsigned char>(text[value])))
	{
		++value;
	}
	return value;
}

std::string jsonString(const std::string& text, const std::string& key)
{
	size_t value = findJsonValue(text, key);
	if (value >= text.size() || text[value] != '"')
	{
		throw std::runtime_error("manifest key is not string: " + key);
	}
	size_t end = text.find('"', value + 1);
	if (end == std::string::npos)
	{
		throw std::runtime_error("manifest string is unterminated: " + key);
	}
	return text.substr(value + 1, end - value - 1);
}

int64_t jsonInt(const std::string& text, const std::string& key)
{
	size_t value = findJsonValue(text, key);
	char* end = nullptr;
	long long parsed = std::strtoll(text.c_str() + value, &end, 10);
	if (end == text.c_str() + value)
	{
		throw std::runtime_error("manifest key is not integer: " + key);
	}
	return static_cast<int64_t>(parsed);
}

bool jsonBool(const std::string& text, const std::string& key)
{
	size_t value = findJsonValue(text, key);
	if (text.compare(value, 4, "true") == 0) return true;
	if (text.compare(value, 5, "false") == 0) return false;
	throw std::runtime_error("manifest key is not boolean: " + key);
}

FixtureManifest loadManifest(const std::string& fixtureDir)
{
	std::string text = readTextFile(joinPath(fixtureDir, "manifest.json"));
	std::string schema = jsonString(text, "schema");
	if (schema != "cuflye-read-alignment-replay-fixture-v0")
	{
		throw std::runtime_error("unsupported read-alignment fixture schema: " + schema);
	}

	FixtureManifest manifest;
	manifest.queryId = jsonInt(text, "query_id");
	manifest.alignmentInputRecords = static_cast<int32_t>(jsonInt(text, "alignment_input_records"));
	manifest.candidateChains = static_cast<int32_t>(jsonInt(text, "candidate_chains"));
	manifest.oracleChains = static_cast<int32_t>(jsonInt(text, "oracle_chains"));
	manifest.params.maximumJump = static_cast<int32_t>(jsonInt(text, "maximum_jump"));
	manifest.params.maxReadOverlap = static_cast<int32_t>(jsonInt(text, "max_read_overlap"));
	manifest.params.minimumOverlap = static_cast<int32_t>(jsonInt(text, "minimum_overlap"));
	manifest.params.maxSeparation = static_cast<int32_t>(jsonInt(text, "max_separation"));
	manifest.readsBaseAlignment = jsonBool(text, "reads_base_alignment");
	return manifest;
}

bool sameReplayParams(const ReplayParams& lhs, const ReplayParams& rhs)
{
	return lhs.maximumJump == rhs.maximumJump && lhs.maxReadOverlap == rhs.maxReadOverlap &&
	       lhs.minimumOverlap == rhs.minimumOverlap && lhs.maxSeparation == rhs.maxSeparation;
}

std::string replayShapeKey(size_t inputRecords, size_t chainDivergenceRows,
                           const ReplayParams& params)
{
	std::ostringstream key;
	key << inputRecords << ":" << chainDivergenceRows << ":" << params.maximumJump << ":"
	    << params.maxReadOverlap << ":" << params.minimumOverlap << ":" << params.maxSeparation;
	return key.str();
}

std::string replayShapeKey(const LoadedFixture& fixture)
{
	return replayShapeKey(fixture.overlaps.size(), fixture.divergenceAccepted.size(),
	                      fixture.manifest.params);
}

std::vector<EdgeOverlap> loadEdgeOverlaps(const std::string& path, int64_t queryId)
{
	std::ifstream input(path);
	if (!input)
	{
		throw std::runtime_error("cannot read edge-overlaps TSV: " + path);
	}
	std::vector<EdgeOverlap> overlaps;
	std::string line;
	size_t lineNumber = 0;
	while (std::getline(input, line))
	{
		++lineNumber;
		auto fields = splitTabs(line);
		if (fields.size() != 14)
		{
			throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
			                         ": expected 14 fields");
		}
		EdgeOverlap record{};
		record.candidateId = std::stoll(fields[0]);
		record.readId = std::stoll(fields[1]);
		record.readBegin = static_cast<int32_t>(std::stoll(fields[2]));
		record.readEnd = static_cast<int32_t>(std::stoll(fields[3]));
		record.readLen = static_cast<int32_t>(std::stoll(fields[4]));
		record.edgeId = std::stoll(fields[5]);
		record.edgeLeftNode = static_cast<int32_t>(std::stoll(fields[6]));
		record.edgeRightNode = static_cast<int32_t>(std::stoll(fields[7]));
		record.edgeSeqId = std::stoll(fields[8]);
		record.edgeBegin = static_cast<int32_t>(std::stoll(fields[9]));
		record.edgeEnd = static_cast<int32_t>(std::stoll(fields[10]));
		record.edgeLen = static_cast<int32_t>(std::stoll(fields[11]));
		record.score = static_cast<int32_t>(std::stoll(fields[12]));
		record.seqDivergence = std::stof(fields[13]);
		if (record.readId != queryId)
		{
			throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
			                         ": read_id does not match manifest query_id");
		}
		if (record.candidateId != static_cast<int64_t>(overlaps.size()))
		{
			throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
			                         ": candidate_id must be contiguous from zero");
		}
		overlaps.push_back(record);
	}
	if (overlaps.empty())
	{
		throw std::runtime_error("edge-overlaps fixture is empty: " + path);
	}
	return overlaps;
}

std::vector<uint8_t> loadDivergenceAccepted(const std::string& path)
{
	std::ifstream input(path);
	if (!input)
	{
		throw std::runtime_error("cannot read chain-divergence TSV: " + path);
	}
	std::vector<uint8_t> accepted;
	std::string line;
	size_t lineNumber = 0;
	while (std::getline(input, line))
	{
		++lineNumber;
		auto fields = splitTabs(line);
		if (fields.size() != 3)
		{
			throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
			                         ": expected 3 fields");
		}
		int64_t chainId = std::stoll(fields[0]);
		if (chainId != static_cast<int64_t>(accepted.size()))
		{
			throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
			                         ": chain_id must be contiguous from zero");
		}
		int64_t flag = std::stoll(fields[2]);
		if (flag != 0 && flag != 1)
		{
			throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
			                         ": accepted flag must be 0 or 1");
		}
		accepted.push_back(static_cast<uint8_t>(flag));
	}
	if (accepted.empty())
	{
		throw std::runtime_error("chain-divergence fixture is empty: " + path);
	}
	return accepted;
}

LoadedFixture loadFixture(const std::string& fixtureDir, bool requireDivergenceAcceptance)
{
	LoadedFixture fixture;
	fixture.fixtureDir = fixtureDir;
	fixture.manifest = loadManifest(fixtureDir);
	fixture.overlaps =
	    loadEdgeOverlaps(joinPath(fixtureDir, "edge-overlaps.tsv"), fixture.manifest.queryId);
	if (requireDivergenceAcceptance)
	{
		fixture.divergenceAccepted =
		    loadDivergenceAccepted(joinPath(fixtureDir, "chain-divergence.tsv"));
	}
	if (fixture.overlaps.size() != static_cast<size_t>(fixture.manifest.alignmentInputRecords))
	{
		throw std::runtime_error("edge-overlap count does not match manifest");
	}
	if (fixture.overlaps.size() > MAX_REPLAY_RECORDS)
	{
		throw std::runtime_error("fixture exceeds M5c bounded CUDA replay record limit");
	}
	return fixture;
}

std::vector<std::string> loadFixtureList(const std::string& path)
{
	std::ifstream input(path);
	if (!input)
	{
		throw std::runtime_error("cannot read batch fixture list: " + path);
	}
	std::vector<std::string> fixtures;
	std::string line;
	while (std::getline(input, line))
	{
		if (line.empty() || line[0] == '#') continue;
		fixtures.push_back(line);
	}
	if (fixtures.empty())
	{
		throw std::runtime_error("batch fixture list is empty: " + path);
	}
	return fixtures;
}

std::vector<LoadedFixture> loadBatchFixtures(const std::string& path, bool allowHeterogeneous,
                                             bool requireDivergenceAcceptance)
{
	std::vector<std::string> fixtureDirs = loadFixtureList(path);
	std::vector<LoadedFixture> fixtures;
	fixtures.reserve(fixtureDirs.size());
	for (const std::string& fixtureDir : fixtureDirs)
	{
		fixtures.push_back(loadFixture(fixtureDir, requireDivergenceAcceptance));
	}
	if (fixtures.empty())
	{
		throw std::runtime_error("batch fixture list is empty after loading");
	}
	if (allowHeterogeneous)
	{
		return fixtures;
	}
	size_t overlapCount = fixtures.front().overlaps.size();
	size_t divergenceCount = fixtures.front().divergenceAccepted.size();
	ReplayParams params = fixtures.front().manifest.params;
	for (const LoadedFixture& fixture : fixtures)
	{
		if (fixture.overlaps.size() != overlapCount)
		{
			throw std::runtime_error(
			    "unsupported read-alignment batch: alignment_input_records differ");
		}
		if (fixture.divergenceAccepted.size() != divergenceCount)
		{
			throw std::runtime_error(
			    "unsupported read-alignment batch: chain-divergence counts differ");
		}
		if (!sameReplayParams(fixture.manifest.params, params))
		{
			throw std::runtime_error("unsupported read-alignment batch: replay parameters differ");
		}
	}
	return fixtures;
}

std::vector<CpuChain> cpuChainReadAlignments(const std::vector<EdgeOverlap>& overlaps,
                                             const ReplayParams& params)
{
	std::vector<CpuChain> active;
	std::vector<CpuChain> frozen;
	for (size_t index = 0; index < overlaps.size(); ++index)
	{
		const EdgeOverlap& edgeAlignment = overlaps[index];
		int32_t maxScore = 0;
		int32_t maxChain = -1;
		size_t numOutdated = 0;

		bool canExtend = edgeAlignment.edgeBegin < params.maximumJump;
		bool canBeExtended = edgeAlignment.edgeLen - edgeAlignment.edgeEnd < params.maximumJump;

		if (canExtend)
		{
			for (size_t chainIndex = 0; chainIndex < active.size(); ++chainIndex)
			{
				const CpuChain& chain = active[chainIndex];
				const EdgeOverlap& prev = overlaps[chain.indices.back()];
				int32_t readDiff = edgeAlignment.readBegin - prev.readEnd;
				int32_t graphLeftDiff = edgeAlignment.edgeBegin;
				int32_t graphRightDiff = prev.edgeLen - prev.edgeEnd;
				bool connected = prev.edgeRightNode == edgeAlignment.edgeLeftNode;
				if (connected && params.maximumJump > readDiff &&
				    readDiff > -params.maxReadOverlap &&
				    graphLeftDiff + graphRightDiff < params.maximumJump)
				{
					int32_t jumpDiv = std::abs(readDiff - (graphLeftDiff + graphRightDiff));
					int32_t gapCost = jumpDiv > 100 ? jumpDiv / 50 : 0;
					int32_t score = chain.score + edgeAlignment.score - gapCost;
					if (score > maxScore)
					{
						maxScore = score;
						maxChain = static_cast<int32_t>(chainIndex);
					}
				}
				if (readDiff > params.maximumJump) ++numOutdated;
			}
		}

		if (maxChain != -1)
		{
			CpuChain next = active[static_cast<size_t>(maxChain)];
			next.indices.push_back(static_cast<int32_t>(index));
			next.score = maxScore;
			active.push_back(next);
		}
		else if (canBeExtended)
		{
			CpuChain next;
			next.indices.push_back(static_cast<int32_t>(index));
			next.score = edgeAlignment.score;
			active.push_back(next);
		}
		else
		{
			CpuChain next;
			next.indices.push_back(static_cast<int32_t>(index));
			next.score = edgeAlignment.score;
			frozen.push_back(next);
		}

		if (numOutdated > active.size() / 2)
		{
			std::vector<CpuChain> newActive;
			for (const CpuChain& chain : active)
			{
				const EdgeOverlap& prev = overlaps[chain.indices.back()];
				bool outdated = edgeAlignment.readBegin - prev.readEnd > params.maximumJump;
				if (outdated)
				{
					frozen.push_back(chain);
				}
				else
				{
					newActive.push_back(chain);
				}
			}
			active.swap(newActive);
		}
	}

	active.insert(active.end(), frozen.begin(), frozen.end());
	std::stable_sort(active.begin(), active.end(), [](const CpuChain& lhs, const CpuChain& rhs)
	                 { return lhs.score > rhs.score; });

	std::vector<CpuChain> accepted;
	for (const CpuChain& chain : active)
	{
		const EdgeOverlap& first = overlaps[chain.indices.front()];
		const EdgeOverlap& last = overlaps[chain.indices.back()];
		int32_t alnLen = last.readEnd - first.readBegin;
		if (alnLen < params.minimumOverlap) continue;

		bool overlapsExisting = false;
		for (const CpuChain& existing : accepted)
		{
			const EdgeOverlap& existingFirst = overlaps[existing.indices.front()];
			const EdgeOverlap& existingLast = overlaps[existing.indices.back()];
			int32_t overlapRate = std::min(last.readEnd, existingLast.readEnd) -
			                      std::max(first.readBegin, existingFirst.readBegin);
			if (overlapRate > params.maxSeparation)
			{
				overlapsExisting = true;
				break;
			}
		}
		if (!overlapsExisting) accepted.push_back(chain);
	}
	return accepted;
}

std::vector<OutputSegment>
buildSegmentsFromCpuChains(const std::vector<CpuChain>& chains,
                           const std::vector<uint8_t>& divergenceAccepted)
{
	if (chains.size() != divergenceAccepted.size())
	{
		throw std::runtime_error("CPU replay chain count differs from divergence rows");
	}
	std::vector<OutputSegment> segments;
	int32_t outputChainId = 0;
	for (size_t chainId = 0; chainId < chains.size(); ++chainId)
	{
		if (!divergenceAccepted[chainId]) continue;
		const CpuChain& chain = chains[chainId];
		for (size_t segmentId = 0; segmentId < chain.indices.size(); ++segmentId)
		{
			OutputSegment segment{};
			segment.chainId = outputChainId;
			segment.segmentId = static_cast<int32_t>(segmentId);
			segment.overlapIndex = chain.indices[segmentId];
			segments.push_back(segment);
		}
		++outputChainId;
	}
	return segments;
}

std::vector<OutputSegment> buildSegmentsFromPreDivergenceCpuChains(
    const std::vector<CpuChain>& chains)
{
	std::vector<OutputSegment> segments;
	int32_t outputChainId = 0;
	for (const CpuChain& chain : chains)
	{
		for (size_t segmentId = 0; segmentId < chain.indices.size(); ++segmentId)
		{
			OutputSegment segment{};
			segment.chainId = outputChainId;
			segment.segmentId = static_cast<int32_t>(segmentId);
			segment.overlapIndex = chain.indices[segmentId];
			segments.push_back(segment);
		}
		++outputChainId;
	}
	return segments;
}

__device__ void initChain(ChainRecord& chain, int32_t parent, int32_t overlapIndex,
                          int32_t firstIndex, int32_t length, int32_t score)
{
	chain.parent = parent;
	chain.overlapIndex = overlapIndex;
	chain.firstIndex = firstIndex;
	chain.lastIndex = overlapIndex;
	chain.length = length;
	chain.score = score;
}

__global__ void readAlignmentChainKernel(const EdgeOverlap* overlaps, int32_t overlapCount,
                                         const uint8_t* divergenceAccepted, int32_t divergenceCount,
                                         ReplayParams params, ChainRecord* chains,
                                         int32_t* activeIds, int32_t* frozenIds,
                                         int32_t* orderedIds, int32_t* acceptedIds,
                                         int32_t* scratch, OutputSegment* output,
                                         int32_t outputCapacity, DeviceSummary* summary)
{
	if (threadIdx.x != 0) return;
	uint32_t batchId = blockIdx.x;
	overlaps += static_cast<size_t>(batchId) * static_cast<size_t>(overlapCount);
	bool emitPreDivergenceChains = divergenceCount == 0;
	if (!emitPreDivergenceChains)
	{
		divergenceAccepted += static_cast<size_t>(batchId) *
		                      static_cast<size_t>(divergenceCount);
	}
	chains += static_cast<size_t>(batchId) * static_cast<size_t>(overlapCount);
	activeIds += static_cast<size_t>(batchId) * static_cast<size_t>(overlapCount);
	frozenIds += static_cast<size_t>(batchId) * static_cast<size_t>(overlapCount);
	orderedIds += static_cast<size_t>(batchId) * static_cast<size_t>(overlapCount);
	acceptedIds += static_cast<size_t>(batchId) * static_cast<size_t>(overlapCount);
	scratch += static_cast<size_t>(batchId) * static_cast<size_t>(overlapCount);
	output += static_cast<size_t>(batchId) * static_cast<size_t>(outputCapacity);
	summary += batchId;
	summary->valid = 0;
	summary->errorCode = 0;
	summary->candidateChains = 0;
	summary->preDivergenceAcceptedChains = 0;
	summary->acceptedChains = 0;
	summary->outputRecords = 0;

	int32_t chainCount = 0;
	int32_t activeCount = 0;
	int32_t frozenCount = 0;
	for (int32_t index = 0; index < overlapCount; ++index)
	{
		EdgeOverlap edgeAlignment = overlaps[index];
		int32_t maxScore = 0;
		int32_t maxChain = -1;
		int32_t numOutdated = 0;

		bool canExtend = edgeAlignment.edgeBegin < params.maximumJump;
		bool canBeExtended = edgeAlignment.edgeLen - edgeAlignment.edgeEnd < params.maximumJump;

		if (canExtend)
		{
			for (int32_t activeIndex = 0; activeIndex < activeCount; ++activeIndex)
			{
				int32_t chainId = activeIds[activeIndex];
				ChainRecord chain = chains[chainId];
				EdgeOverlap prev = overlaps[chain.lastIndex];
				int32_t readDiff = edgeAlignment.readBegin - prev.readEnd;
				int32_t graphLeftDiff = edgeAlignment.edgeBegin;
				int32_t graphRightDiff = prev.edgeLen - prev.edgeEnd;
				bool connected = prev.edgeRightNode == edgeAlignment.edgeLeftNode;
				if (connected && params.maximumJump > readDiff &&
				    readDiff > -params.maxReadOverlap &&
				    graphLeftDiff + graphRightDiff < params.maximumJump)
				{
					int32_t jumpDiv = abs(readDiff - (graphLeftDiff + graphRightDiff));
					int32_t gapCost = jumpDiv > 100 ? jumpDiv / 50 : 0;
					int32_t score = chain.score + edgeAlignment.score - gapCost;
					if (score > maxScore)
					{
						maxScore = score;
						maxChain = chainId;
					}
				}
				if (readDiff > params.maximumJump) ++numOutdated;
			}
		}

		if (maxChain != -1)
		{
			ChainRecord parent = chains[maxChain];
			initChain(chains[chainCount], maxChain, index, parent.firstIndex, parent.length + 1,
			          maxScore);
			activeIds[activeCount++] = chainCount++;
		}
		else if (canBeExtended)
		{
			initChain(chains[chainCount], -1, index, index, 1, edgeAlignment.score);
			activeIds[activeCount++] = chainCount++;
		}
		else
		{
			initChain(chains[chainCount], -1, index, index, 1, edgeAlignment.score);
			frozenIds[frozenCount++] = chainCount++;
		}

		if (numOutdated > activeCount / 2)
		{
			int32_t newActiveCount = 0;
			for (int32_t activeIndex = 0; activeIndex < activeCount; ++activeIndex)
			{
				int32_t chainId = activeIds[activeIndex];
				EdgeOverlap prev = overlaps[chains[chainId].lastIndex];
				bool outdated = edgeAlignment.readBegin - prev.readEnd > params.maximumJump;
				if (outdated)
				{
					frozenIds[frozenCount++] = chainId;
				}
				else
				{
					activeIds[newActiveCount++] = chainId;
				}
			}
			activeCount = newActiveCount;
		}
	}

	for (int32_t index = 0; index < frozenCount; ++index)
	{
		activeIds[activeCount++] = frozenIds[index];
	}
	for (int32_t index = 0; index < activeCount; ++index)
	{
		orderedIds[index] = activeIds[index];
	}
	for (int32_t index = 0; index < activeCount; ++index)
	{
		int32_t best = index;
		for (int32_t next = index + 1; next < activeCount; ++next)
		{
			if (chains[orderedIds[next]].score > chains[orderedIds[best]].score)
			{
				best = next;
			}
		}
		int32_t tmp = orderedIds[index];
		orderedIds[index] = orderedIds[best];
		orderedIds[best] = tmp;
	}

	int32_t preDivergenceAccepted = 0;
	for (int32_t ordered = 0; ordered < activeCount; ++ordered)
	{
		int32_t chainId = orderedIds[ordered];
		ChainRecord chain = chains[chainId];
		EdgeOverlap first = overlaps[chain.firstIndex];
		EdgeOverlap last = overlaps[chain.lastIndex];
		int32_t alnLen = last.readEnd - first.readBegin;
		if (alnLen < params.minimumOverlap) continue;

		bool overlapsExisting = false;
		for (int32_t accepted = 0; accepted < preDivergenceAccepted; ++accepted)
		{
			ChainRecord existing = chains[acceptedIds[accepted]];
			EdgeOverlap existingFirst = overlaps[existing.firstIndex];
			EdgeOverlap existingLast = overlaps[existing.lastIndex];
			int32_t overlapRate = min(last.readEnd, existingLast.readEnd) -
			                      max(first.readBegin, existingFirst.readBegin);
			if (overlapRate > params.maxSeparation)
			{
				overlapsExisting = true;
				break;
			}
		}
		if (!overlapsExisting)
		{
			acceptedIds[preDivergenceAccepted++] = chainId;
		}
	}

	if (!emitPreDivergenceChains && preDivergenceAccepted != divergenceCount)
	{
		summary->errorCode = 1;
		return;
	}

	int32_t outputRecordCount = 0;
	int32_t outputChainId = 0;
	for (int32_t chainIndex = 0; chainIndex < preDivergenceAccepted; ++chainIndex)
	{
		if (!emitPreDivergenceChains && !divergenceAccepted[chainIndex]) continue;
		int32_t chainId = acceptedIds[chainIndex];
		ChainRecord chain = chains[chainId];
		if (chain.length > overlapCount)
		{
			summary->errorCode = 2;
			return;
		}
		int32_t pos = chainId;
		for (int32_t segment = chain.length - 1; segment >= 0; --segment)
		{
			scratch[segment] = chains[pos].overlapIndex;
			pos = chains[pos].parent;
		}
		for (int32_t segment = 0; segment < chain.length; ++segment)
		{
			if (outputRecordCount >= outputCapacity)
			{
				summary->errorCode = 3;
				return;
			}
			output[outputRecordCount].chainId = outputChainId;
			output[outputRecordCount].segmentId = segment;
			output[outputRecordCount].overlapIndex = scratch[segment];
			++outputRecordCount;
		}
		++outputChainId;
	}

	summary->valid = 1;
	summary->candidateChains = preDivergenceAccepted;
	summary->preDivergenceAcceptedChains = preDivergenceAccepted;
	summary->acceptedChains = outputChainId;
	summary->outputRecords = outputRecordCount;
}

std::vector<OutputSegment> cudaSegmentsToVector(const std::vector<OutputSegment>& raw, size_t count)
{
	if (count > raw.size())
	{
		throw std::runtime_error("CUDA output count exceeds copied segment buffer");
	}
	return std::vector<OutputSegment>(raw.begin(), raw.begin() + static_cast<long>(count));
}

void writeReadAlignment(const std::string& path, const std::vector<EdgeOverlap>& overlaps,
                        const std::vector<OutputSegment>& segments)
{
	ensureParentDirectory(path);
	std::ofstream output(path);
	if (!output)
	{
		throw std::runtime_error("cannot write read-alignment TSV: " + path);
	}
	output << std::setprecision(9);
	for (const OutputSegment& segment : segments)
	{
		const EdgeOverlap& item = overlaps[segment.overlapIndex];
		output << segment.chainId << "\t" << segment.segmentId << "\t" << item.readId << "\t"
		       << item.readBegin << "\t" << item.readEnd << "\t" << item.readLen << "\t"
		       << item.edgeId << "\t" << item.edgeSeqId << "\t" << item.edgeBegin << "\t"
		       << item.edgeEnd << "\t" << item.edgeLen << "\t" << item.score << "\t";
		if (item.seqDivergence == 0.0f)
		{
			output << "0";
		}
		else
		{
			output << item.seqDivergence;
		}
		output << "\n";
	}
}

size_t checkedOutputCapacity(size_t overlapCount)
{
	if (overlapCount == 0 || overlapCount > MAX_REPLAY_RECORDS)
	{
		throw std::runtime_error("unsupported replay fixture record count");
	}
	if (overlapCount > std::numeric_limits<size_t>::max() / overlapCount)
	{
		throw std::runtime_error("output capacity overflow");
	}
	return overlapCount * overlapCount;
}

size_t checkedMul(size_t lhs, size_t rhs, const std::string& label)
{
	if (lhs != 0 && rhs > std::numeric_limits<size_t>::max() / lhs)
	{
		throw std::runtime_error(label + " overflows size_t");
	}
	return lhs * rhs;
}

size_t checkedAdd(size_t lhs, size_t rhs, const std::string& label)
{
	if (rhs > std::numeric_limits<size_t>::max() - lhs)
	{
		throw std::runtime_error(label + " overflows size_t");
	}
	return lhs + rhs;
}

std::vector<std::vector<size_t>>
groupFixtureIndicesByShape(const std::vector<LoadedFixture>& fixtures)
{
	std::map<std::string, std::vector<size_t>> grouped;
	for (size_t index = 0; index < fixtures.size(); ++index)
	{
		grouped[replayShapeKey(fixtures[index])].push_back(index);
	}

	std::vector<std::vector<size_t>> groups;
	groups.reserve(grouped.size());
	for (const auto& item : grouped)
	{
		groups.push_back(item.second);
	}
	return groups;
}

std::vector<LoadedFixture> selectFixturesByIndex(const std::vector<LoadedFixture>& fixtures,
                                                 const std::vector<size_t>& indices)
{
	std::vector<LoadedFixture> selected;
	selected.reserve(indices.size());
	for (size_t index : indices)
	{
		selected.push_back(fixtures[index]);
	}
	return selected;
}

RunSummary runCpu(const Options& options, const LoadedFixture& fixture,
                  std::vector<OutputSegment>& segments)
{
	RunSummary summary;
	summary.backend = "cpu";
	summary.cudaExecutionMode = "none";
	summary.batchSize = options.replicateFixture;
	summary.inputRecords = fixture.overlaps.size();
	summary.minInputRecords = summary.inputRecords;
	summary.maxInputRecords = summary.inputRecords;
	summary.totalInputRecords = checkedMul(fixture.overlaps.size(), options.replicateFixture,
	                                       "CPU replicated total input records");
	auto start = Clock::now();
	std::vector<CpuChain> representativeChains;
	std::vector<OutputSegment> representativeSegments;
	for (uint32_t repeat = 0; repeat < options.replicateFixture; ++repeat)
	{
		std::vector<CpuChain> chains =
		    cpuChainReadAlignments(fixture.overlaps, fixture.manifest.params);
		std::vector<OutputSegment> repeatedSegments =
		    options.emitPreDivergenceChains
		        ? buildSegmentsFromPreDivergenceCpuChains(chains)
		        : buildSegmentsFromCpuChains(chains, fixture.divergenceAccepted);
		if (repeat == 0)
		{
			representativeChains = chains;
			representativeSegments = repeatedSegments;
		}
	}
	segments = representativeSegments;
	auto end = Clock::now();
	summary.cpuChainMs = elapsedMs(start, end);
	summary.candidateChains = representativeChains.size();
	summary.preDivergenceAcceptedChains = representativeChains.size();
	if (options.emitPreDivergenceChains)
	{
		summary.acceptedChains = representativeChains.size();
	}
	else
	{
		summary.acceptedChains = 0;
		for (uint8_t accepted : fixture.divergenceAccepted)
		{
			if (accepted) ++summary.acceptedChains;
		}
	}
	summary.outputRecords = segments.size();
	summary.totalBeforeJsonMs = summary.cpuChainMs;
	return summary;
}

RunSummary runCpuBatch(const Options& options, const std::vector<LoadedFixture>& fixtures,
                       std::vector<std::vector<OutputSegment>>& segmentsByFixture)
{
	if (fixtures.empty())
	{
		throw std::runtime_error("batch fixture set is empty");
	}

	RunSummary summary;
	summary.backend = "cpu";
	summary.cudaExecutionMode = "none";
	summary.batchSize = fixtures.size();
	summary.inputRecords = fixtures.front().overlaps.size();
	summary.minInputRecords = summary.inputRecords;
	summary.maxInputRecords = summary.inputRecords;
	summary.totalInputRecords =
	    checkedMul(summary.inputRecords, fixtures.size(), "CPU batch total input records");

	segmentsByFixture.clear();
	segmentsByFixture.reserve(fixtures.size());
	auto start = Clock::now();
	for (const LoadedFixture& fixture : fixtures)
	{
		std::vector<CpuChain> chains =
		    cpuChainReadAlignments(fixture.overlaps, fixture.manifest.params);
		std::vector<OutputSegment> segments =
		    options.emitPreDivergenceChains
		        ? buildSegmentsFromPreDivergenceCpuChains(chains)
		        : buildSegmentsFromCpuChains(chains, fixture.divergenceAccepted);
		summary.candidateChains += chains.size();
		summary.preDivergenceAcceptedChains += chains.size();
		if (options.emitPreDivergenceChains)
		{
			summary.acceptedChains += chains.size();
		}
		else
		{
			for (uint8_t accepted : fixture.divergenceAccepted)
			{
				if (accepted) ++summary.acceptedChains;
			}
		}
		summary.outputRecords += segments.size();
		segmentsByFixture.push_back(std::move(segments));
	}
	auto end = Clock::now();
	summary.cpuChainMs = elapsedMs(start, end);
	summary.totalBeforeJsonMs = summary.cpuChainMs;
	return summary;
}

size_t cudaRequiredBytes(size_t overlapCount, size_t divergenceCount, size_t outputCapacity,
                         size_t batchSize)
{
	size_t overlapItems = checkedMul(batchSize, overlapCount, "CUDA overlap item count");
	size_t divergenceItems = checkedMul(batchSize, divergenceCount, "CUDA divergence item count");
	size_t outputItems = checkedMul(batchSize, outputCapacity, "CUDA output item count");
	size_t intScratchBytes = checkedMul(checkedMul(overlapItems, 5, "CUDA int scratch item count"),
	                                    sizeof(int32_t), "CUDA int scratch byte count");
	size_t total = checkedMul(overlapItems, sizeof(EdgeOverlap), "CUDA overlap byte count");
	total = checkedAdd(total,
	                   checkedMul(divergenceItems, sizeof(uint8_t), "CUDA divergence byte count"),
	                   "CUDA required byte count");
	total =
	    checkedAdd(total, checkedMul(overlapItems, sizeof(ChainRecord), "CUDA chain byte count"),
	               "CUDA required byte count");
	total = checkedAdd(total, intScratchBytes, "CUDA required byte count");
	total =
	    checkedAdd(total, checkedMul(outputItems, sizeof(OutputSegment), "CUDA output byte count"),
	               "CUDA required byte count");
	total =
	    checkedAdd(total, checkedMul(batchSize, sizeof(DeviceSummary), "CUDA summary byte count"),
	               "CUDA required byte count");
	return total;
}

RunSummary runCuda(const Options& options, const LoadedFixture& fixture,
                   std::vector<OutputSegment>& segments)
{
	RunSummary summary;
	summary.backend = "cuda";
	summary.cudaExecutionMode = "per-run-allocation";
	summary.device = options.device;
	summary.batchSize = options.replicateFixture;
	summary.inputRecords = fixture.overlaps.size();
	summary.minInputRecords = summary.inputRecords;
	summary.maxInputRecords = summary.inputRecords;
	summary.totalInputRecords = checkedMul(fixture.overlaps.size(), options.replicateFixture,
	                                       "CUDA replicated total input records");
	size_t overlapCount = fixture.overlaps.size();
	size_t divergenceCount =
	    options.emitPreDivergenceChains ? 0 : fixture.divergenceAccepted.size();
	size_t outputCapacity = checkedOutputCapacity(overlapCount);
	size_t batchSize = options.replicateFixture;
	size_t overlapItems = checkedMul(overlapCount, batchSize, "CUDA replicated overlap items");
	size_t divergenceItems =
	    checkedMul(divergenceCount, batchSize, "CUDA replicated divergence items");
	size_t outputItems = checkedMul(outputCapacity, batchSize, "CUDA replicated output items");
	summary.requiredBytes =
	    cudaRequiredBytes(overlapCount, divergenceCount, outputCapacity, batchSize);
	if (options.hasMemoryBudget &&
	    summary.requiredBytes > static_cast<size_t>(options.memoryBudgetBytes))
	{
		throw std::runtime_error("CUDA memory budget exceeded for read-alignment replay");
	}

	auto setupStart = Clock::now();
	std::vector<EdgeOverlap> packedOverlaps;
	packedOverlaps.reserve(overlapItems);
	std::vector<uint8_t> packedDivergence;
	packedDivergence.reserve(divergenceItems);
	for (size_t index = 0; index < batchSize; ++index)
	{
		packedOverlaps.insert(packedOverlaps.end(), fixture.overlaps.begin(),
		                      fixture.overlaps.end());
		if (!options.emitPreDivergenceChains)
		{
			packedDivergence.insert(packedDivergence.end(), fixture.divergenceAccepted.begin(),
			                        fixture.divergenceAccepted.end());
		}
	}
	cuflye::cuda_raii::checkCuda(cudaSetDevice(options.device), "set CUDA device");
	cudaDeviceProp props{};
	cuflye::cuda_raii::checkCuda(cudaGetDeviceProperties(&props, options.device),
	                             "get CUDA device properties");
	summary.deviceName = props.name;
	cuflye::cuda_raii::checkCuda(cudaMemGetInfo(&summary.freeBytes, &summary.totalBytes),
	                             "query CUDA memory");
	auto setupEnd = Clock::now();
	summary.setupMs = elapsedMs(setupStart, setupEnd);

	auto allocStart = Clock::now();
	cuflye::cuda_raii::DeviceBuffer<EdgeOverlap> dOverlaps(
	    checkedMul(packedOverlaps.size(), sizeof(EdgeOverlap), "read alignment overlap bytes"),
	    "read alignment edge overlaps");
	cuflye::cuda_raii::DeviceBuffer<uint8_t> dDivergence(
	    checkedMul(packedDivergence.size(), sizeof(uint8_t), "read alignment divergence bytes"),
	    "chain divergence flags");
	cuflye::cuda_raii::DeviceBuffer<ChainRecord> dChains(
	    checkedMul(overlapItems, sizeof(ChainRecord), "read alignment chain bytes"),
	    "read alignment chains");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dActive(
	    checkedMul(overlapItems, sizeof(int32_t), "active chain id bytes"), "active chain ids");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dFrozen(
	    checkedMul(overlapItems, sizeof(int32_t), "frozen chain id bytes"), "frozen chain ids");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dOrdered(
	    checkedMul(overlapItems, sizeof(int32_t), "ordered chain id bytes"), "ordered chain ids");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dAccepted(
	    checkedMul(overlapItems, sizeof(int32_t), "accepted chain id bytes"), "accepted chain ids");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dScratch(
	    checkedMul(overlapItems, sizeof(int32_t), "chain reconstruction scratch bytes"),
	    "chain reconstruction scratch");
	cuflye::cuda_raii::DeviceBuffer<OutputSegment> dOutput(
	    checkedMul(outputItems, sizeof(OutputSegment), "read alignment output bytes"),
	    "read alignment output segments");
	cuflye::cuda_raii::DeviceBuffer<DeviceSummary> dSummary(
	    checkedMul(batchSize, sizeof(DeviceSummary), "read alignment summary bytes"),
	    "read alignment summary");
	auto allocEnd = Clock::now();
	summary.deviceAllocationMs = elapsedMs(allocStart, allocEnd);

	auto h2dStart = Clock::now();
	cuflye::cuda_raii::checkCuda(cudaMemcpy(dOverlaps.get(), packedOverlaps.data(),
	                                        checkedMul(packedOverlaps.size(), sizeof(EdgeOverlap),
	                                                   "copy read alignment overlap bytes"),
	                                        cudaMemcpyHostToDevice),
	                             "copy read alignment overlaps to device");
	if (!packedDivergence.empty())
	{
		cuflye::cuda_raii::checkCuda(
		    cudaMemcpy(dDivergence.get(), packedDivergence.data(),
		               checkedMul(packedDivergence.size(), sizeof(uint8_t),
		                          "copy read alignment divergence bytes"),
		               cudaMemcpyHostToDevice),
		    "copy chain divergence flags to device");
	}
	auto h2dEnd = Clock::now();
	summary.hostToDeviceMs = elapsedMs(h2dStart, h2dEnd);

	auto kernelStart = Clock::now();
	readAlignmentChainKernel<<<static_cast<unsigned int>(batchSize), 1>>>(
	    dOverlaps.get(), static_cast<int32_t>(overlapCount), dDivergence.get(),
	    static_cast<int32_t>(divergenceCount), fixture.manifest.params,
	    dChains.get(), dActive.get(), dFrozen.get(), dOrdered.get(), dAccepted.get(),
	    dScratch.get(), dOutput.get(), static_cast<int32_t>(outputCapacity), dSummary.get());
	cuflye::cuda_raii::checkCuda(cudaGetLastError(), "launch read alignment chain kernel");
	cuflye::cuda_raii::checkCuda(cudaDeviceSynchronize(),
	                             "synchronize read alignment chain kernel");
	auto kernelEnd = Clock::now();
	summary.kernelMs = elapsedMs(kernelStart, kernelEnd);

	std::vector<DeviceSummary> deviceSummaries(batchSize);
	std::vector<OutputSegment> rawSegments(outputCapacity);
	auto d2hStart = Clock::now();
	cuflye::cuda_raii::checkCuda(cudaMemcpy(deviceSummaries.data(), dSummary.get(),
	                                        checkedMul(batchSize, sizeof(DeviceSummary),
	                                                   "copy read alignment summary bytes"),
	                                        cudaMemcpyDeviceToHost),
	                             "copy read alignment summary to host");
	if (deviceSummaries[0].outputRecords > 0)
	{
		cuflye::cuda_raii::checkCuda(
		    cudaMemcpy(rawSegments.data(), dOutput.get(),
		               checkedMul(static_cast<size_t>(deviceSummaries[0].outputRecords),
		                          sizeof(OutputSegment), "copy read alignment output bytes"),
		               cudaMemcpyDeviceToHost),
		    "copy read alignment output to host");
	}
	auto d2hEnd = Clock::now();
	summary.deviceToHostMs = elapsedMs(d2hStart, d2hEnd);

	auto finalizeStart = Clock::now();
	for (size_t index = 0; index < deviceSummaries.size(); ++index)
	{
		if (!deviceSummaries[index].valid)
		{
			throw std::runtime_error("read alignment CUDA replay kernel failed at batch " +
			                         std::to_string(index) + " with code " +
			                         std::to_string(deviceSummaries[index].errorCode));
		}
	}
	segments =
	    cudaSegmentsToVector(rawSegments, static_cast<size_t>(deviceSummaries[0].outputRecords));
	auto finalizeEnd = Clock::now();
	summary.finalizeMs = elapsedMs(finalizeStart, finalizeEnd);
	summary.candidateChains = static_cast<size_t>(deviceSummaries[0].candidateChains);
	summary.preDivergenceAcceptedChains =
	    static_cast<size_t>(deviceSummaries[0].preDivergenceAcceptedChains);
	summary.acceptedChains = static_cast<size_t>(deviceSummaries[0].acceptedChains);
	summary.outputRecords = segments.size();
	summary.totalBeforeJsonMs = summary.setupMs + summary.deviceAllocationMs +
	                            summary.hostToDeviceMs + summary.kernelMs + summary.deviceToHostMs +
	                            summary.finalizeMs;
	return summary;
}

RunSummary runCudaBatch(const Options& options, const std::vector<LoadedFixture>& fixtures,
                        std::vector<std::vector<OutputSegment>>& segmentsByFixture)
{
	if (fixtures.empty())
	{
		throw std::runtime_error("batch fixture set is empty");
	}

	RunSummary summary;
	summary.backend = "cuda";
	summary.cudaExecutionMode = "per-run-allocation";
	summary.device = options.device;
	summary.batchSize = fixtures.size();
	summary.inputRecords = fixtures.front().overlaps.size();
	summary.minInputRecords = summary.inputRecords;
	summary.maxInputRecords = summary.inputRecords;
	summary.totalInputRecords =
	    checkedMul(summary.inputRecords, fixtures.size(), "CUDA batch total input records");
	size_t overlapCount = fixtures.front().overlaps.size();
	size_t divergenceCount =
	    options.emitPreDivergenceChains ? 0 : fixtures.front().divergenceAccepted.size();
	size_t outputCapacity = checkedOutputCapacity(overlapCount);
	size_t batchSize = fixtures.size();
	size_t overlapItems = checkedMul(overlapCount, batchSize, "CUDA batch overlap items");
	size_t divergenceItems = checkedMul(divergenceCount, batchSize, "CUDA batch divergence items");
	size_t outputItems = checkedMul(outputCapacity, batchSize, "CUDA batch output items");
	if (batchSize > static_cast<size_t>(std::numeric_limits<unsigned int>::max()) ||
	    overlapCount > static_cast<size_t>(std::numeric_limits<int32_t>::max()) ||
	    divergenceCount > static_cast<size_t>(std::numeric_limits<int32_t>::max()) ||
	    outputCapacity > static_cast<size_t>(std::numeric_limits<int32_t>::max()))
	{
		throw std::runtime_error("unsupported CUDA batch shape exceeds kernel ABI limits");
	}
	summary.requiredBytes =
	    cudaRequiredBytes(overlapCount, divergenceCount, outputCapacity, batchSize);
	if (options.hasMemoryBudget &&
	    summary.requiredBytes > static_cast<size_t>(options.memoryBudgetBytes))
	{
		throw std::runtime_error("CUDA memory budget exceeded for read-alignment batch");
	}

	auto setupStart = Clock::now();
	std::vector<EdgeOverlap> packedOverlaps;
	packedOverlaps.reserve(overlapItems);
	std::vector<uint8_t> packedDivergence;
	packedDivergence.reserve(divergenceItems);
	for (const LoadedFixture& fixture : fixtures)
	{
		packedOverlaps.insert(packedOverlaps.end(), fixture.overlaps.begin(),
		                      fixture.overlaps.end());
		if (!options.emitPreDivergenceChains)
		{
			packedDivergence.insert(packedDivergence.end(), fixture.divergenceAccepted.begin(),
			                        fixture.divergenceAccepted.end());
		}
	}
	cuflye::cuda_raii::checkCuda(cudaSetDevice(options.device), "set CUDA device");
	cudaDeviceProp props{};
	cuflye::cuda_raii::checkCuda(cudaGetDeviceProperties(&props, options.device),
	                             "get CUDA device properties");
	summary.deviceName = props.name;
	cuflye::cuda_raii::checkCuda(cudaMemGetInfo(&summary.freeBytes, &summary.totalBytes),
	                             "query CUDA memory");
	auto setupEnd = Clock::now();
	summary.setupMs = elapsedMs(setupStart, setupEnd);

	auto allocStart = Clock::now();
	cuflye::cuda_raii::DeviceBuffer<EdgeOverlap> dOverlaps(
	    checkedMul(packedOverlaps.size(), sizeof(EdgeOverlap),
	               "read alignment batch overlap bytes"),
	    "read alignment batch overlaps");
	cuflye::cuda_raii::DeviceBuffer<uint8_t> dDivergence(
	    checkedMul(packedDivergence.size(), sizeof(uint8_t),
	               "read alignment batch divergence bytes"),
	    "read alignment batch divergence");
	cuflye::cuda_raii::DeviceBuffer<ChainRecord> dChains(
	    checkedMul(overlapItems, sizeof(ChainRecord), "read alignment batch chain bytes"),
	    "read alignment batch chains");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dActive(
	    checkedMul(overlapItems, sizeof(int32_t), "batch active chain id bytes"),
	    "batch active chain ids");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dFrozen(
	    checkedMul(overlapItems, sizeof(int32_t), "batch frozen chain id bytes"),
	    "batch frozen chain ids");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dOrdered(
	    checkedMul(overlapItems, sizeof(int32_t), "batch ordered chain id bytes"),
	    "batch ordered chain ids");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dAccepted(
	    checkedMul(overlapItems, sizeof(int32_t), "batch accepted chain id bytes"),
	    "batch accepted chain ids");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dScratch(
	    checkedMul(overlapItems, sizeof(int32_t), "batch chain reconstruction scratch bytes"),
	    "batch chain reconstruction scratch");
	cuflye::cuda_raii::DeviceBuffer<OutputSegment> dOutput(
	    checkedMul(outputItems, sizeof(OutputSegment), "read alignment batch output bytes"),
	    "read alignment batch output segments");
	cuflye::cuda_raii::DeviceBuffer<DeviceSummary> dSummary(
	    checkedMul(batchSize, sizeof(DeviceSummary), "read alignment batch summary bytes"),
	    "read alignment batch summary");
	auto allocEnd = Clock::now();
	summary.deviceAllocationMs = elapsedMs(allocStart, allocEnd);

	auto h2dStart = Clock::now();
	cuflye::cuda_raii::checkCuda(cudaMemcpy(dOverlaps.get(), packedOverlaps.data(),
	                                        checkedMul(packedOverlaps.size(), sizeof(EdgeOverlap),
	                                                   "copy read alignment batch overlap bytes"),
	                                        cudaMemcpyHostToDevice),
	                             "copy read alignment batch overlaps to device");
	if (!packedDivergence.empty())
	{
		cuflye::cuda_raii::checkCuda(
		    cudaMemcpy(dDivergence.get(), packedDivergence.data(),
		               checkedMul(packedDivergence.size(), sizeof(uint8_t),
		                          "copy read alignment batch divergence bytes"),
		               cudaMemcpyHostToDevice),
		    "copy read alignment batch divergence to device");
	}
	auto h2dEnd = Clock::now();
	summary.hostToDeviceMs = elapsedMs(h2dStart, h2dEnd);

	auto kernelStart = Clock::now();
	readAlignmentChainKernel<<<static_cast<unsigned int>(batchSize), 1>>>(
	    dOverlaps.get(), static_cast<int32_t>(overlapCount), dDivergence.get(),
	    static_cast<int32_t>(divergenceCount), fixtures.front().manifest.params, dChains.get(),
	    dActive.get(), dFrozen.get(), dOrdered.get(), dAccepted.get(), dScratch.get(),
	    dOutput.get(), static_cast<int32_t>(outputCapacity), dSummary.get());
	cuflye::cuda_raii::checkCuda(cudaGetLastError(), "launch read alignment batch chain kernel");
	cuflye::cuda_raii::checkCuda(cudaDeviceSynchronize(),
	                             "synchronize read alignment batch chain kernel");
	auto kernelEnd = Clock::now();
	summary.kernelMs = elapsedMs(kernelStart, kernelEnd);

	std::vector<DeviceSummary> deviceSummaries(batchSize);
	auto d2hStart = Clock::now();
	cuflye::cuda_raii::checkCuda(cudaMemcpy(deviceSummaries.data(), dSummary.get(),
	                                        checkedMul(batchSize, sizeof(DeviceSummary),
	                                                   "copy read alignment batch summary bytes"),
	                                        cudaMemcpyDeviceToHost),
	                             "copy read alignment batch summary to host");
	for (size_t index = 0; index < batchSize; ++index)
	{
		if (!deviceSummaries[index].valid)
		{
			continue;
		}
		if (deviceSummaries[index].outputRecords < 0 ||
		    static_cast<size_t>(deviceSummaries[index].outputRecords) > outputCapacity)
		{
			throw std::runtime_error("CUDA batch output count exceeds fixture capacity");
		}
	}
	segmentsByFixture.clear();
	segmentsByFixture.resize(batchSize);
	for (size_t index = 0; index < batchSize; ++index)
	{
		if (!deviceSummaries[index].valid) continue;
		size_t recordCount = static_cast<size_t>(deviceSummaries[index].outputRecords);
		if (recordCount == 0) continue;
		segmentsByFixture[index].resize(recordCount);
		const OutputSegment* deviceOutput =
		    dOutput.get() + checkedMul(index, outputCapacity, "CUDA output offset");
		cuflye::cuda_raii::checkCuda(
		    cudaMemcpy(segmentsByFixture[index].data(), deviceOutput,
		               checkedMul(recordCount, sizeof(OutputSegment),
		                          "copy read alignment batch output bytes"),
		               cudaMemcpyDeviceToHost),
		    "copy read alignment batch output to host");
	}
	auto d2hEnd = Clock::now();
	summary.deviceToHostMs = elapsedMs(d2hStart, d2hEnd);

	auto finalizeStart = Clock::now();
	for (size_t index = 0; index < deviceSummaries.size(); ++index)
	{
		if (!deviceSummaries[index].valid)
		{
			throw std::runtime_error("read alignment CUDA batch kernel failed at batch " +
			                         std::to_string(index) + " with code " +
			                         std::to_string(deviceSummaries[index].errorCode));
		}
		summary.candidateChains += static_cast<size_t>(deviceSummaries[index].candidateChains);
		summary.preDivergenceAcceptedChains +=
		    static_cast<size_t>(deviceSummaries[index].preDivergenceAcceptedChains);
		summary.acceptedChains += static_cast<size_t>(deviceSummaries[index].acceptedChains);
		summary.outputRecords += static_cast<size_t>(deviceSummaries[index].outputRecords);
	}
	auto finalizeEnd = Clock::now();
	summary.finalizeMs = elapsedMs(finalizeStart, finalizeEnd);
	summary.totalBeforeJsonMs = summary.setupMs + summary.deviceAllocationMs +
	                            summary.hostToDeviceMs + summary.kernelMs + summary.deviceToHostMs +
	                            summary.finalizeMs;
	return summary;
}

RunSummary runGroupedBatch(const Options& options, const std::vector<LoadedFixture>& fixtures,
                           std::vector<std::vector<OutputSegment>>& segmentsByFixture)
{
	if (fixtures.empty())
	{
		throw std::runtime_error("batch fixture set is empty");
	}
	std::vector<std::vector<size_t>> groups = groupFixtureIndicesByShape(fixtures);
	RunSummary summary;
	summary.backend = options.backend;
	summary.cudaExecutionMode = options.backend == "cuda" ? "per-run-allocation" : "none";
	summary.device = options.device;
	summary.batchSize = fixtures.size();
	summary.shapeGroups = groups.size();
	summary.minInputRecords = fixtures.front().overlaps.size();
	summary.maxInputRecords = fixtures.front().overlaps.size();
	segmentsByFixture.clear();
	segmentsByFixture.resize(fixtures.size());
	bool deviceFieldsInitialized = false;

	for (const LoadedFixture& fixture : fixtures)
	{
		summary.totalInputRecords = checkedAdd(summary.totalInputRecords, fixture.overlaps.size(),
		                                       "heterogeneous batch total input records");
		summary.minInputRecords = std::min(summary.minInputRecords, fixture.overlaps.size());
		summary.maxInputRecords = std::max(summary.maxInputRecords, fixture.overlaps.size());
	}
	if (groups.size() == 1)
	{
		summary.inputRecords = fixtures.front().overlaps.size();
	}

	for (const std::vector<size_t>& group : groups)
	{
		std::vector<LoadedFixture> selected = selectFixturesByIndex(fixtures, group);
		std::vector<std::vector<OutputSegment>> groupSegments;
		RunSummary groupSummary = options.backend == "cuda"
		                              ? runCudaBatch(options, selected, groupSegments)
		                              : runCpuBatch(options, selected, groupSegments);
		if (groupSegments.size() != group.size())
		{
			throw std::runtime_error("heterogeneous batch group output count mismatch");
		}
		for (size_t index = 0; index < group.size(); ++index)
		{
			segmentsByFixture[group[index]] = std::move(groupSegments[index]);
		}

		summary.setupMs += groupSummary.setupMs;
		summary.deviceAllocationMs += groupSummary.deviceAllocationMs;
		summary.hostToDeviceMs += groupSummary.hostToDeviceMs;
		summary.kernelMs += groupSummary.kernelMs;
		summary.cpuChainMs += groupSummary.cpuChainMs;
		summary.deviceToHostMs += groupSummary.deviceToHostMs;
		summary.finalizeMs += groupSummary.finalizeMs;
		summary.totalBeforeJsonMs += groupSummary.totalBeforeJsonMs;
		summary.candidateChains += groupSummary.candidateChains;
		summary.preDivergenceAcceptedChains += groupSummary.preDivergenceAcceptedChains;
		summary.acceptedChains += groupSummary.acceptedChains;
		summary.outputRecords += groupSummary.outputRecords;
		summary.requiredBytes = std::max(summary.requiredBytes, groupSummary.requiredBytes);
		if (groupSummary.backend == "cuda" && !deviceFieldsInitialized)
		{
			summary.deviceName = groupSummary.deviceName;
			summary.freeBytes = groupSummary.freeBytes;
			summary.totalBytes = groupSummary.totalBytes;
			deviceFieldsInitialized = true;
		}
	}
	return summary;
}

CudaPersistentArena buildCudaPersistentArena(const Options& options,
                                             const std::vector<LoadedFixture>& fixtures)
{
	if (fixtures.empty())
	{
		throw std::runtime_error("batch fixture set is empty");
	}
	std::vector<std::vector<size_t>> groups = groupFixtureIndicesByShape(fixtures);
	size_t totalRequiredBytes = 0;
	for (const std::vector<size_t>& group : groups)
	{
		const LoadedFixture& firstFixture = fixtures[group.front()];
		size_t overlapCount = firstFixture.overlaps.size();
		size_t divergenceCount =
		    options.emitPreDivergenceChains ? 0 : firstFixture.divergenceAccepted.size();
		size_t outputCapacity = checkedOutputCapacity(overlapCount);
		size_t batchSize = group.size();
		if (batchSize > static_cast<size_t>(std::numeric_limits<unsigned int>::max()) ||
		    overlapCount > static_cast<size_t>(std::numeric_limits<int32_t>::max()) ||
		    divergenceCount > static_cast<size_t>(std::numeric_limits<int32_t>::max()) ||
		    outputCapacity > static_cast<size_t>(std::numeric_limits<int32_t>::max()))
		{
			throw std::runtime_error("unsupported CUDA arena shape exceeds kernel ABI limits");
		}
		totalRequiredBytes =
		    checkedAdd(totalRequiredBytes,
		               cudaRequiredBytes(overlapCount, divergenceCount, outputCapacity, batchSize),
		               "persistent CUDA arena byte count");
	}
	if (options.hasMemoryBudget &&
	    totalRequiredBytes > static_cast<size_t>(options.memoryBudgetBytes))
	{
		throw std::runtime_error("CUDA memory budget exceeded for persistent read-alignment arena");
	}

	CudaPersistentArena arenaContext;
	arenaContext.device = options.device;
	arenaContext.requiredBytes = totalRequiredBytes;
	arenaContext.fixtureCount = fixtures.size();
	arenaContext.minInputRecords = fixtures.front().overlaps.size();
	arenaContext.maxInputRecords = fixtures.front().overlaps.size();
	for (const LoadedFixture& fixture : fixtures)
	{
		arenaContext.totalInputRecords =
		    checkedAdd(arenaContext.totalInputRecords, fixture.overlaps.size(),
		               "persistent arena total input records");
		arenaContext.minInputRecords =
		    std::min(arenaContext.minInputRecords, fixture.overlaps.size());
		arenaContext.maxInputRecords =
		    std::max(arenaContext.maxInputRecords, fixture.overlaps.size());
	}

	auto setupStart = Clock::now();
	cuflye::cuda_raii::checkCuda(cudaSetDevice(options.device), "set CUDA device");
	cudaDeviceProp props{};
	cuflye::cuda_raii::checkCuda(cudaGetDeviceProperties(&props, options.device),
	                             "get CUDA device properties");
	arenaContext.deviceName = props.name;
	cuflye::cuda_raii::checkCuda(cudaMemGetInfo(&arenaContext.freeBytes, &arenaContext.totalBytes),
	                             "query CUDA memory");
	auto setupEnd = Clock::now();
	arenaContext.setupMs = elapsedMs(setupStart, setupEnd);

	arenaContext.groups.reserve(groups.size());
	for (const std::vector<size_t>& group : groups)
	{
		const LoadedFixture& firstFixture = fixtures[group.front()];
		CudaGroupArena arena;
		arena.originalIndices = group;
		arena.params = firstFixture.manifest.params;
		arena.overlapCount = firstFixture.overlaps.size();
		arena.divergenceCount =
		    options.emitPreDivergenceChains ? 0 : firstFixture.divergenceAccepted.size();
		arena.outputCapacity = checkedOutputCapacity(arena.overlapCount);
		arena.batchSize = group.size();
		arena.requiredBytes = cudaRequiredBytes(arena.overlapCount, arena.divergenceCount,
		                                        arena.outputCapacity, arena.batchSize);
		size_t overlapItems =
		    checkedMul(arena.overlapCount, arena.batchSize, "persistent arena overlap items");
		size_t divergenceItems =
		    checkedMul(arena.divergenceCount, arena.batchSize, "persistent arena divergence items");
		size_t outputItems =
		    checkedMul(arena.outputCapacity, arena.batchSize, "persistent arena output items");

		std::vector<EdgeOverlap> packedOverlaps;
		packedOverlaps.reserve(overlapItems);
		std::vector<uint8_t> packedDivergence;
		packedDivergence.reserve(divergenceItems);
		for (size_t fixtureIndex : group)
		{
			const LoadedFixture& fixture = fixtures[fixtureIndex];
			packedOverlaps.insert(packedOverlaps.end(), fixture.overlaps.begin(),
			                      fixture.overlaps.end());
			if (!options.emitPreDivergenceChains)
			{
				packedDivergence.insert(packedDivergence.end(), fixture.divergenceAccepted.begin(),
				                        fixture.divergenceAccepted.end());
			}
		}

		auto allocStart = Clock::now();
		arena.dOverlaps.allocate(checkedMul(packedOverlaps.size(), sizeof(EdgeOverlap),
		                                    "persistent arena overlap bytes"),
		                         "persistent read alignment overlaps");
		arena.dDivergence.allocate(checkedMul(packedDivergence.size(), sizeof(uint8_t),
		                                      "persistent arena divergence bytes"),
		                           "persistent read alignment divergence");
		arena.dChains.allocate(
		    checkedMul(overlapItems, sizeof(ChainRecord), "persistent arena chain bytes"),
		    "persistent read alignment chains");
		arena.dActive.allocate(
		    checkedMul(overlapItems, sizeof(int32_t), "persistent arena active id bytes"),
		    "persistent active chain ids");
		arena.dFrozen.allocate(
		    checkedMul(overlapItems, sizeof(int32_t), "persistent arena frozen id bytes"),
		    "persistent frozen chain ids");
		arena.dOrdered.allocate(
		    checkedMul(overlapItems, sizeof(int32_t), "persistent arena ordered id bytes"),
		    "persistent ordered chain ids");
		arena.dAccepted.allocate(
		    checkedMul(overlapItems, sizeof(int32_t), "persistent arena accepted id bytes"),
		    "persistent accepted chain ids");
		arena.dScratch.allocate(
		    checkedMul(overlapItems, sizeof(int32_t), "persistent arena scratch bytes"),
		    "persistent chain reconstruction scratch");
		arena.dOutput.allocate(
		    checkedMul(outputItems, sizeof(OutputSegment), "persistent arena output bytes"),
		    "persistent read alignment output segments");
		arena.dSummary.allocate(
		    checkedMul(arena.batchSize, sizeof(DeviceSummary), "persistent arena summary bytes"),
		    "persistent read alignment summary");
		auto allocEnd = Clock::now();
		arenaContext.deviceAllocationMs += elapsedMs(allocStart, allocEnd);

		auto h2dStart = Clock::now();
		cuflye::cuda_raii::checkCuda(
		    cudaMemcpy(arena.dOverlaps.get(), packedOverlaps.data(),
		               checkedMul(packedOverlaps.size(), sizeof(EdgeOverlap),
		                          "copy persistent arena overlap bytes"),
		               cudaMemcpyHostToDevice),
		    "copy persistent read alignment overlaps to device");
		if (!packedDivergence.empty())
		{
			cuflye::cuda_raii::checkCuda(
			    cudaMemcpy(arena.dDivergence.get(), packedDivergence.data(),
			               checkedMul(packedDivergence.size(), sizeof(uint8_t),
			                          "copy persistent arena divergence bytes"),
			               cudaMemcpyHostToDevice),
			    "copy persistent read alignment divergence to device");
		}
		auto h2dEnd = Clock::now();
		arenaContext.hostToDeviceMs += elapsedMs(h2dStart, h2dEnd);

		arenaContext.groups.push_back(std::move(arena));
	}
	return arenaContext;
}

RunSummary runCudaPersistentArenaOnce(const CudaPersistentArena& arenaContext, bool bulkOutput,
                                      std::vector<std::vector<OutputSegment>>& segmentsByFixture)
{
	RunSummary summary;
	summary.backend = "cuda";
	summary.cudaExecutionMode = bulkOutput ? "persistent-arena-bulk-output" : "persistent-arena";
	summary.device = arenaContext.device;
	summary.deviceName = arenaContext.deviceName;
	summary.freeBytes = arenaContext.freeBytes;
	summary.totalBytes = arenaContext.totalBytes;
	summary.requiredBytes = arenaContext.requiredBytes;
	summary.batchSize = arenaContext.fixtureCount;
	summary.shapeGroups = arenaContext.groups.size();
	summary.totalInputRecords = arenaContext.totalInputRecords;
	summary.minInputRecords = arenaContext.minInputRecords;
	summary.maxInputRecords = arenaContext.maxInputRecords;
	if (arenaContext.groups.size() == 1)
	{
		summary.inputRecords = arenaContext.groups.front().overlapCount;
	}
	segmentsByFixture.clear();
	segmentsByFixture.resize(arenaContext.fixtureCount);

	auto kernelStart = Clock::now();
	for (const CudaGroupArena& arena : arenaContext.groups)
	{
		readAlignmentChainKernel<<<static_cast<unsigned int>(arena.batchSize), 1>>>(
		    arena.dOverlaps.get(), static_cast<int32_t>(arena.overlapCount),
		    arena.dDivergence.get(), static_cast<int32_t>(arena.divergenceCount), arena.params,
		    arena.dChains.get(), arena.dActive.get(), arena.dFrozen.get(), arena.dOrdered.get(),
		    arena.dAccepted.get(), arena.dScratch.get(), arena.dOutput.get(),
		    static_cast<int32_t>(arena.outputCapacity), arena.dSummary.get());
		cuflye::cuda_raii::checkCuda(cudaGetLastError(),
		                             "launch persistent read alignment batch kernel");
	}
	cuflye::cuda_raii::checkCuda(cudaDeviceSynchronize(),
	                             "synchronize persistent read alignment batch kernels");
	auto kernelEnd = Clock::now();
	summary.kernelMs = elapsedMs(kernelStart, kernelEnd);

	auto d2hStart = Clock::now();
	std::vector<std::vector<DeviceSummary>> summariesByGroup;
	summariesByGroup.reserve(arenaContext.groups.size());
	for (const CudaGroupArena& arena : arenaContext.groups)
	{
		std::vector<DeviceSummary> deviceSummaries(arena.batchSize);
		cuflye::cuda_raii::checkCuda(cudaMemcpy(deviceSummaries.data(), arena.dSummary.get(),
		                                        checkedMul(arena.batchSize, sizeof(DeviceSummary),
		                                                   "copy persistent arena summary bytes"),
		                                        cudaMemcpyDeviceToHost),
		                             "copy persistent read alignment summary to host");
		bool hasOutputRecords = false;
		for (size_t index = 0; index < arena.batchSize; ++index)
		{
			if (!deviceSummaries[index].valid) continue;
			if (deviceSummaries[index].outputRecords < 0 ||
			    static_cast<size_t>(deviceSummaries[index].outputRecords) > arena.outputCapacity)
			{
				throw std::runtime_error("persistent CUDA output count exceeds fixture capacity");
			}
			hasOutputRecords = hasOutputRecords || deviceSummaries[index].outputRecords > 0;
		}

		if (bulkOutput && hasOutputRecords)
		{
			size_t outputItems = checkedMul(arena.batchSize, arena.outputCapacity,
			                                "persistent CUDA bulk output item count");
			std::vector<OutputSegment> rawGroupOutput(outputItems);
			cuflye::cuda_raii::checkCuda(
			    cudaMemcpy(rawGroupOutput.data(), arena.dOutput.get(),
			               checkedMul(outputItems, sizeof(OutputSegment),
			                          "copy persistent arena bulk output bytes"),
			               cudaMemcpyDeviceToHost),
			    "copy persistent read alignment bulk output to host");
			for (size_t index = 0; index < arena.batchSize; ++index)
			{
				if (!deviceSummaries[index].valid) continue;
				size_t recordCount = static_cast<size_t>(deviceSummaries[index].outputRecords);
				if (recordCount == 0) continue;
				size_t originalIndex = arena.originalIndices[index];
				size_t outputOffset =
				    checkedMul(index, arena.outputCapacity, "persistent CUDA output offset");
				size_t outputEnd =
				    checkedAdd(outputOffset, recordCount, "persistent CUDA bulk output end");
				if (outputEnd > rawGroupOutput.size())
				{
					throw std::runtime_error("persistent CUDA bulk output slice is out of bounds");
				}
				const OutputSegment* outputBegin = rawGroupOutput.data() + outputOffset;
				segmentsByFixture[originalIndex].assign(outputBegin, outputBegin + recordCount);
			}
		}
		else if (!bulkOutput)
		{
			for (size_t index = 0; index < arena.batchSize; ++index)
			{
				if (!deviceSummaries[index].valid) continue;
				size_t recordCount = static_cast<size_t>(deviceSummaries[index].outputRecords);
				if (recordCount == 0) continue;
				size_t originalIndex = arena.originalIndices[index];
				segmentsByFixture[originalIndex].resize(recordCount);
				const OutputSegment* deviceOutput =
				    arena.dOutput.get() +
				    checkedMul(index, arena.outputCapacity, "persistent CUDA output offset");
				cuflye::cuda_raii::checkCuda(
				    cudaMemcpy(segmentsByFixture[originalIndex].data(), deviceOutput,
				               checkedMul(recordCount, sizeof(OutputSegment),
				                          "copy persistent arena output bytes"),
				               cudaMemcpyDeviceToHost),
				    "copy persistent read alignment output to host");
			}
		}
		summariesByGroup.push_back(std::move(deviceSummaries));
	}
	auto d2hEnd = Clock::now();
	summary.deviceToHostMs = elapsedMs(d2hStart, d2hEnd);

	auto finalizeStart = Clock::now();
	for (size_t groupIndex = 0; groupIndex < arenaContext.groups.size(); ++groupIndex)
	{
		const std::vector<DeviceSummary>& deviceSummaries = summariesByGroup[groupIndex];
		for (size_t index = 0; index < deviceSummaries.size(); ++index)
		{
			if (!deviceSummaries[index].valid)
			{
				throw std::runtime_error(
				    "persistent read alignment CUDA batch kernel failed at group " +
				    std::to_string(groupIndex) + " batch " + std::to_string(index) + " with code " +
				    std::to_string(deviceSummaries[index].errorCode));
			}
			summary.candidateChains += static_cast<size_t>(deviceSummaries[index].candidateChains);
			summary.preDivergenceAcceptedChains +=
			    static_cast<size_t>(deviceSummaries[index].preDivergenceAcceptedChains);
			summary.acceptedChains += static_cast<size_t>(deviceSummaries[index].acceptedChains);
			summary.outputRecords += static_cast<size_t>(deviceSummaries[index].outputRecords);
		}
	}
	auto finalizeEnd = Clock::now();
	summary.finalizeMs = elapsedMs(finalizeStart, finalizeEnd);
	summary.totalBeforeJsonMs = summary.kernelMs + summary.deviceToHostMs + summary.finalizeMs;
	return summary;
}

RunSummary
runCudaPersistentArenaBenchmark(const Options& options, const std::vector<LoadedFixture>& fixtures,
                                std::vector<std::vector<OutputSegment>>& segmentsByFixture)
{
	CudaPersistentArena arenaContext = buildCudaPersistentArena(options, fixtures);
	RunSummary summary =
	    runCudaPersistentArenaBenchmarkWithExistingArena(options, arenaContext, segmentsByFixture);
	return summary;
}

RunSummary runCudaPersistentArenaBenchmarkWithExistingArena(
    const Options& options, const CudaPersistentArena& arenaContext,
    std::vector<std::vector<OutputSegment>>& segmentsByFixture)
{
	std::vector<std::vector<OutputSegment>> scratch;
	for (uint32_t index = 0; index < options.warmupRuns; ++index)
	{
		(void)runCudaPersistentArenaOnce(arenaContext, options.cudaPersistentBulkOutput, scratch);
	}

	std::vector<RunSummary> timedRuns;
	for (uint32_t index = 0; index < options.benchmarkRuns; ++index)
	{
		RunSummary summary = runCudaPersistentArenaOnce(
		    arenaContext, options.cudaPersistentBulkOutput, segmentsByFixture);
		timedRuns.push_back(summary);
	}
	RunSummary summary = timedRuns.back();
	attachBenchmarkStats(summary, timedRuns, options.warmupRuns);
	summary.oneTimeSetupMs = arenaContext.setupMs;
	summary.oneTimeDeviceAllocationMs = arenaContext.deviceAllocationMs;
	summary.oneTimeHostToDeviceMs = arenaContext.hostToDeviceMs;
	summary.oneTimeTotalMs =
	    summary.oneTimeSetupMs + summary.oneTimeDeviceAllocationMs + summary.oneTimeHostToDeviceMs;
	return summary;
}

void attachBenchmarkStats(RunSummary& summary, const std::vector<RunSummary>& timedRuns,
                          uint32_t warmupRuns)
{
	if (timedRuns.empty())
	{
		throw std::runtime_error("cannot summarize empty benchmark run set");
	}
	summary.warmupRuns = warmupRuns;
	summary.timedRuns = static_cast<uint32_t>(timedRuns.size());
	double total = 0.0;
	double core = 0.0;
	summary.benchmarkMinTotalMs = timedRuns[0].totalBeforeJsonMs;
	summary.benchmarkMaxTotalMs = timedRuns[0].totalBeforeJsonMs;
	for (const RunSummary& run : timedRuns)
	{
		total += run.totalBeforeJsonMs;
		core += run.backend == "cuda" ? run.kernelMs : run.cpuChainMs;
		summary.benchmarkMinTotalMs = std::min(summary.benchmarkMinTotalMs, run.totalBeforeJsonMs);
		summary.benchmarkMaxTotalMs = std::max(summary.benchmarkMaxTotalMs, run.totalBeforeJsonMs);
	}
	summary.benchmarkMeanTotalMs = total / static_cast<double>(timedRuns.size());
	summary.benchmarkMeanCoreMs = core / static_cast<double>(timedRuns.size());
}

RunSummary runBenchmark(const Options& options, const LoadedFixture& fixture,
                        std::vector<OutputSegment>& segments)
{
	std::vector<OutputSegment> scratch;
	for (uint32_t index = 0; index < options.warmupRuns; ++index)
	{
		if (options.backend == "cuda")
		{
			(void)runCuda(options, fixture, scratch);
		}
		else
		{
			(void)runCpu(options, fixture, scratch);
		}
	}

	std::vector<RunSummary> timedRuns;
	for (uint32_t index = 0; index < options.benchmarkRuns; ++index)
	{
		RunSummary summary = options.backend == "cuda" ? runCuda(options, fixture, segments)
		                                               : runCpu(options, fixture, segments);
		timedRuns.push_back(summary);
	}
	RunSummary summary = timedRuns.back();
	attachBenchmarkStats(summary, timedRuns, options.warmupRuns);
	return summary;
}

RunSummary runBatchBenchmark(const Options& options, const std::vector<LoadedFixture>& fixtures,
                             std::vector<std::vector<OutputSegment>>& segmentsByFixture)
{
	if (options.cudaPersistentArena)
	{
		return runCudaPersistentArenaBenchmark(options, fixtures, segmentsByFixture);
	}

	std::vector<std::vector<OutputSegment>> scratch;
	for (uint32_t index = 0; index < options.warmupRuns; ++index)
	{
		if (options.allowHeterogeneousBatch)
		{
			(void)runGroupedBatch(options, fixtures, scratch);
		}
		else if (options.backend == "cuda")
		{
			(void)runCudaBatch(options, fixtures, scratch);
		}
		else
		{
			(void)runCpuBatch(options, fixtures, scratch);
		}
	}

	std::vector<RunSummary> timedRuns;
	for (uint32_t index = 0; index < options.benchmarkRuns; ++index)
	{
		RunSummary summary =
		    options.allowHeterogeneousBatch
		        ? runGroupedBatch(options, fixtures, segmentsByFixture)
		        : (options.backend == "cuda" ? runCudaBatch(options, fixtures, segmentsByFixture)
		                                     : runCpuBatch(options, fixtures, segmentsByFixture));
		timedRuns.push_back(summary);
	}
	RunSummary summary = timedRuns.back();
	attachBenchmarkStats(summary, timedRuns, options.warmupRuns);
	return summary;
}

void writeJsonSummary(const std::string& path, const Options& options,
                      const FixtureManifest& manifest, const RunSummary& summary)
{
	ensureParentDirectory(path);
	std::ofstream output(path);
	if (!output)
	{
		throw std::runtime_error("cannot write JSON summary: " + path);
	}
	output << std::fixed << std::setprecision(6);
	output << "{\n"
	       << "  \"schema\": \"cuflye-cuda-read-alignment-chain-replay-v0\",\n"
	       << "  \"status\": \"ok\",\n"
	       << "  \"backend\": \"" << jsonEscape(summary.backend) << "\",\n"
	       << "  \"cuda_execution_mode\": ";
	if (summary.backend == "cuda")
	{
		output << "\"" << jsonEscape(summary.cudaExecutionMode) << "\",\n";
	}
	else
	{
		output << "null,\n";
	}
	output << "  \"fixture_dir\": \"" << jsonEscape(options.fixtureDir) << "\",\n"
	       << "  \"output_tsv\": \"" << jsonEscape(options.outputTsv) << "\",\n"
	       << "  \"query_id\": " << manifest.queryId << ",\n"
	       << "  \"batch_size\": " << summary.batchSize << ",\n"
	       << "  \"input_records\": " << summary.inputRecords << ",\n"
	       << "  \"total_input_records\": " << summary.totalInputRecords << ",\n"
	       << "  \"candidate_chains\": " << summary.candidateChains << ",\n"
	       << "  \"pre_divergence_accepted_chains\": " << summary.preDivergenceAcceptedChains
	       << ",\n"
	       << "  \"accepted_chains\": " << summary.acceptedChains << ",\n"
	       << "  \"output_records\": " << summary.outputRecords << ",\n";
	if (summary.backend == "cuda")
	{
		output << "  \"device\": {\n"
		       << "    \"id\": " << summary.device << ",\n"
		       << "    \"name\": \"" << jsonEscape(summary.deviceName) << "\",\n"
		       << "    \"free_bytes\": " << summary.freeBytes << ",\n"
		       << "    \"total_bytes\": " << summary.totalBytes << "\n"
		       << "  },\n";
	}
	else
	{
		output << "  \"device\": null,\n";
	}
	output << "  \"memory\": {\n"
	       << "    \"required_bytes\": " << summary.requiredBytes;
	if (options.hasMemoryBudget)
	{
		output << ",\n    \"budget_bytes\": " << options.memoryBudgetBytes << "\n";
	}
	else
	{
		output << "\n";
	}
	output << "  },\n"
	       << "  \"timing_ms\": {\n"
	       << "    \"setup\": " << summary.setupMs << ",\n"
	       << "    \"device_allocation\": " << summary.deviceAllocationMs << ",\n"
	       << "    \"host_to_device\": " << summary.hostToDeviceMs << ",\n"
	       << "    \"one_time_setup\": " << summary.oneTimeSetupMs << ",\n"
	       << "    \"one_time_device_allocation\": " << summary.oneTimeDeviceAllocationMs << ",\n"
	       << "    \"one_time_host_to_device\": " << summary.oneTimeHostToDeviceMs << ",\n"
	       << "    \"one_time_total\": " << summary.oneTimeTotalMs << ",\n"
	       << "    \"kernel\": " << summary.kernelMs << ",\n"
	       << "    \"cpu_chain\": " << summary.cpuChainMs << ",\n"
	       << "    \"device_to_host\": " << summary.deviceToHostMs << ",\n"
	       << "    \"finalize\": " << summary.finalizeMs << ",\n"
	       << "    \"write_output\": " << summary.writeMs << ",\n"
	       << "    \"total_before_json\": " << summary.totalBeforeJsonMs << "\n"
	       << "  },\n"
	       << "  \"benchmark\": {\n"
	       << "    \"warmup_runs\": " << summary.warmupRuns << ",\n"
	       << "    \"timed_runs\": " << summary.timedRuns << ",\n"
	       << "    \"mean_total_before_json_ms\": " << summary.benchmarkMeanTotalMs << ",\n"
	       << "    \"min_total_before_json_ms\": " << summary.benchmarkMinTotalMs << ",\n"
	       << "    \"max_total_before_json_ms\": " << summary.benchmarkMaxTotalMs << ",\n"
	       << "    \"mean_core_ms\": " << summary.benchmarkMeanCoreMs << "\n"
	       << "  },\n"
	       << "  \"supported_shape\": {\n"
	       << "    \"reads_base_alignment\": " << (manifest.readsBaseAlignment ? "true" : "false")
	       << ",\n"
	       << "    \"output_mode\": \""
	       << (options.emitPreDivergenceChains ? "pre-divergence-chains"
	                                           : "post-divergence-accepted-chains")
	       << "\",\n"
	       << "    \"uses_fixture_divergence_acceptance\": "
	       << (options.emitPreDivergenceChains ? "false" : "true") << ",\n"
	       << "    \"representative_output_only\": true,\n"
	       << "    \"max_replay_records\": " << MAX_REPLAY_RECORDS << "\n"
	       << "  }\n"
	       << "}\n";
}

std::vector<BatchFixtureOutput>
writeBatchReadAlignments(const Options& options, const std::vector<LoadedFixture>& fixtures,
                         const std::vector<std::vector<OutputSegment>>& segmentsByFixture)
{
	if (fixtures.size() != segmentsByFixture.size())
	{
		throw std::runtime_error("batch output count differs from fixture count");
	}
	ensureDirectory(options.batchOutputDir);
	std::vector<BatchFixtureOutput> outputs;
	outputs.reserve(fixtures.size());
	for (size_t index = 0; index < fixtures.size(); ++index)
	{
		const LoadedFixture& fixture = fixtures[index];
		std::string name = baseName(fixture.fixtureDir);
		if (name.empty()) name = "fixture_" + std::to_string(index);
		std::string outputTsv =
		    joinPath(joinPath(options.batchOutputDir, name), "read-alignment.tsv");
		writeReadAlignment(outputTsv, fixture.overlaps, segmentsByFixture[index]);

		BatchFixtureOutput output;
		output.fixtureDir = fixture.fixtureDir;
		output.outputTsv = outputTsv;
		output.queryId = fixture.manifest.queryId;
		output.inputRecords = fixture.overlaps.size();
		output.chainDivergenceRows = fixture.divergenceAccepted.size();
		output.outputRecords = segmentsByFixture[index].size();
		output.params = fixture.manifest.params;
		outputs.push_back(output);
	}
	return outputs;
}

std::vector<BatchShapeOutputSummary>
summarizeBatchShapes(const std::vector<BatchFixtureOutput>& fixtureOutputs)
{
	std::map<std::string, BatchShapeOutputSummary> grouped;
	for (const BatchFixtureOutput& fixture : fixtureOutputs)
	{
		std::string key =
		    replayShapeKey(fixture.inputRecords, fixture.chainDivergenceRows, fixture.params);
		BatchShapeOutputSummary& shape = grouped[key];
		if (shape.fixtureCount == 0)
		{
			shape.inputRecords = fixture.inputRecords;
			shape.chainDivergenceRows = fixture.chainDivergenceRows;
			shape.params = fixture.params;
		}
		++shape.fixtureCount;
		shape.totalInputRecords =
		    checkedAdd(shape.totalInputRecords, fixture.inputRecords, "shape total input records");
		shape.outputRecords =
		    checkedAdd(shape.outputRecords, fixture.outputRecords, "shape output records");
		shape.queryIds.push_back(fixture.queryId);
	}

	std::vector<BatchShapeOutputSummary> shapes;
	shapes.reserve(grouped.size());
	for (auto& item : grouped)
	{
		shapes.push_back(std::move(item.second));
	}
	return shapes;
}

void writeBatchJsonSummary(const std::string& path, const Options& options,
                           const RunSummary& summary,
                           const std::vector<BatchFixtureOutput>& fixtureOutputs)
{
	ensureParentDirectory(path);
	std::ofstream output(path);
	if (!output)
	{
		throw std::runtime_error("cannot write batch JSON summary: " + path);
	}
	std::vector<BatchShapeOutputSummary> shapeSummaries = summarizeBatchShapes(fixtureOutputs);
	output << std::fixed << std::setprecision(6);
	output << "{\n"
	       << "  \"schema\": \"cuflye-cuda-read-alignment-chain-replay-batch-v0\",\n"
	       << "  \"status\": \"ok\",\n"
	       << "  \"backend\": \"" << jsonEscape(summary.backend) << "\",\n"
	       << "  \"cuda_execution_mode\": ";
	if (summary.backend == "cuda")
	{
		output << "\"" << jsonEscape(summary.cudaExecutionMode) << "\",\n";
	}
	else
	{
		output << "null,\n";
	}
	output << "  \"batch_fixtures_file\": \"" << jsonEscape(options.batchFixturesFile) << "\",\n"
	       << "  \"batch_output_dir\": \"" << jsonEscape(options.batchOutputDir) << "\",\n"
	       << "  \"fixture_count\": " << fixtureOutputs.size() << ",\n"
	       << "  \"batch_size\": " << summary.batchSize << ",\n"
	       << "  \"heterogeneous_batch\": " << (options.allowHeterogeneousBatch ? "true" : "false")
	       << ",\n"
	       << "  \"shape_group_count\": " << summary.shapeGroups << ",\n";
	if (summary.inputRecords == 0)
	{
		output << "  \"input_records_per_fixture\": null,\n";
	}
	else
	{
		output << "  \"input_records_per_fixture\": " << summary.inputRecords << ",\n";
	}
	output << "  \"min_input_records_per_fixture\": " << summary.minInputRecords << ",\n"
	       << "  \"max_input_records_per_fixture\": " << summary.maxInputRecords << ",\n"
	       << "  \"total_input_records\": " << summary.totalInputRecords << ",\n"
	       << "  \"candidate_chains\": " << summary.candidateChains << ",\n"
	       << "  \"pre_divergence_accepted_chains\": " << summary.preDivergenceAcceptedChains
	       << ",\n"
	       << "  \"accepted_chains\": " << summary.acceptedChains << ",\n"
	       << "  \"output_records\": " << summary.outputRecords << ",\n";
	if (summary.backend == "cuda")
	{
		output << "  \"device\": {\n"
		       << "    \"id\": " << summary.device << ",\n"
		       << "    \"name\": \"" << jsonEscape(summary.deviceName) << "\",\n"
		       << "    \"free_bytes\": " << summary.freeBytes << ",\n"
		       << "    \"total_bytes\": " << summary.totalBytes << "\n"
		       << "  },\n";
	}
	else
	{
		output << "  \"device\": null,\n";
	}
	output << "  \"memory\": {\n"
	       << "    \"required_bytes\": " << summary.requiredBytes;
	if (options.hasMemoryBudget)
	{
		output << ",\n    \"budget_bytes\": " << options.memoryBudgetBytes << "\n";
	}
	else
	{
		output << "\n";
	}
	output << "  },\n"
	       << "  \"timing_ms\": {\n"
	       << "    \"setup\": " << summary.setupMs << ",\n"
	       << "    \"device_allocation\": " << summary.deviceAllocationMs << ",\n"
	       << "    \"host_to_device\": " << summary.hostToDeviceMs << ",\n"
	       << "    \"one_time_setup\": " << summary.oneTimeSetupMs << ",\n"
	       << "    \"one_time_device_allocation\": " << summary.oneTimeDeviceAllocationMs << ",\n"
	       << "    \"one_time_host_to_device\": " << summary.oneTimeHostToDeviceMs << ",\n"
	       << "    \"one_time_total\": " << summary.oneTimeTotalMs << ",\n"
	       << "    \"kernel\": " << summary.kernelMs << ",\n"
	       << "    \"cpu_chain\": " << summary.cpuChainMs << ",\n"
	       << "    \"device_to_host\": " << summary.deviceToHostMs << ",\n"
	       << "    \"finalize\": " << summary.finalizeMs << ",\n"
	       << "    \"write_output\": " << summary.writeMs << ",\n"
	       << "    \"total_before_json\": " << summary.totalBeforeJsonMs << "\n"
	       << "  },\n"
	       << "  \"benchmark\": {\n"
	       << "    \"warmup_runs\": " << summary.warmupRuns << ",\n"
	       << "    \"timed_runs\": " << summary.timedRuns << ",\n"
	       << "    \"mean_total_before_json_ms\": " << summary.benchmarkMeanTotalMs << ",\n"
	       << "    \"min_total_before_json_ms\": " << summary.benchmarkMinTotalMs << ",\n"
	       << "    \"max_total_before_json_ms\": " << summary.benchmarkMaxTotalMs << ",\n"
	       << "    \"mean_core_ms\": " << summary.benchmarkMeanCoreMs << "\n"
	       << "  },\n"
	       << "  \"supported_shape\": {\n"
	       << "    \"real_multi_fixture_batch\": true,\n"
	       << "    \"heterogeneous_grouping_enabled\": "
	       << (options.allowHeterogeneousBatch ? "true" : "false") << ",\n"
	       << "    \"same_alignment_input_records_required\": "
	       << (options.allowHeterogeneousBatch ? "false" : "true") << ",\n"
	       << "    \"same_chain_divergence_count_required\": "
	       << (options.allowHeterogeneousBatch ? "false" : "true") << ",\n"
	       << "    \"same_replay_parameters_required\": "
	       << (options.allowHeterogeneousBatch ? "false" : "true") << ",\n"
	       << "    \"same_shape_required_within_group\": true,\n"
	       << "    \"output_mode\": \""
	       << (options.emitPreDivergenceChains ? "pre-divergence-chains"
	                                           : "post-divergence-accepted-chains")
	       << "\",\n"
	       << "    \"uses_fixture_divergence_acceptance\": "
	       << (options.emitPreDivergenceChains ? "false" : "true") << ",\n"
	       << "    \"representative_output_only\": false,\n"
	       << "    \"max_replay_records\": " << MAX_REPLAY_RECORDS << "\n"
	       << "  },\n"
	       << "  \"shape_groups\": [\n";
	for (size_t index = 0; index < shapeSummaries.size(); ++index)
	{
		const BatchShapeOutputSummary& shape = shapeSummaries[index];
		output << "    {\n"
		       << "      \"input_records_per_fixture\": " << shape.inputRecords << ",\n"
		       << "      \"chain_divergence_rows\": " << shape.chainDivergenceRows << ",\n"
		       << "      \"fixture_count\": " << shape.fixtureCount << ",\n"
		       << "      \"total_input_records\": " << shape.totalInputRecords << ",\n"
		       << "      \"output_records\": " << shape.outputRecords << ",\n"
		       << "      \"replay_parameters\": {\n"
		       << "        \"maximum_jump\": " << shape.params.maximumJump << ",\n"
		       << "        \"max_read_overlap\": " << shape.params.maxReadOverlap << ",\n"
		       << "        \"minimum_overlap\": " << shape.params.minimumOverlap << ",\n"
		       << "        \"max_separation\": " << shape.params.maxSeparation << "\n"
		       << "      },\n"
		       << "      \"query_ids\": [";
		for (size_t queryIndex = 0; queryIndex < shape.queryIds.size(); ++queryIndex)
		{
			if (queryIndex != 0) output << ", ";
			output << shape.queryIds[queryIndex];
		}
		output << "]\n"
		       << "    }";
		if (index + 1 != shapeSummaries.size()) output << ",";
		output << "\n";
	}
	output << "  ],\n"
	       << "  \"fixtures\": [\n";
	for (size_t index = 0; index < fixtureOutputs.size(); ++index)
	{
		const BatchFixtureOutput& fixture = fixtureOutputs[index];
		output << "    {\n"
		       << "      \"fixture_dir\": \"" << jsonEscape(fixture.fixtureDir) << "\",\n"
		       << "      \"output_tsv\": \"" << jsonEscape(fixture.outputTsv) << "\",\n"
		       << "      \"query_id\": " << fixture.queryId << ",\n"
		       << "      \"input_records\": " << fixture.inputRecords << ",\n"
		       << "      \"chain_divergence_rows\": " << fixture.chainDivergenceRows << ",\n"
		       << "      \"output_records\": " << fixture.outputRecords << "\n"
		       << "    }";
		if (index + 1 != fixtureOutputs.size()) output << ",";
		output << "\n";
	}
	output << "  ]\n"
	       << "}\n";
}

bool sameSessionArenaRequest(const ReadAlignmentSessionCache& cache,
                             const ReadAlignmentWorkerRequest& request)
{
	return cache.initialized &&
	       cache.batchFixturesFile == request.options.batchFixturesFile &&
	       cache.device == request.options.device &&
	       cache.hasMemoryBudget == request.options.hasMemoryBudget &&
	       cache.memoryBudgetBytes == request.options.memoryBudgetBytes &&
	       cache.emitPreDivergenceChains == request.options.emitPreDivergenceChains &&
	       cache.allowHeterogeneousBatch == request.options.allowHeterogeneousBatch;
}

std::vector<LoadedFixture> loadReadAlignmentWorkerFixtures(
    const ReadAlignmentWorkerRequest& request)
{
	std::vector<LoadedFixture> fixtures = loadBatchFixtures(
	    request.options.batchFixturesFile, request.options.allowHeterogeneousBatch,
	    !request.options.emitPreDivergenceChains);
	if (request.hasExpectedFixtureCount &&
	    fixtures.size() != request.expectedFixtureCount)
	{
		throw std::runtime_error("read-alignment worker expected fixture count mismatch");
	}
	return fixtures;
}

ReadAlignmentWorkerRequest parseReadAlignmentWorkerRequestObject(const std::string& text)
{
	std::map<std::string, std::string> fields = parseFlatJsonObject(text);
	ReadAlignmentWorkerRequest request;
	request.schema = requireJsonField(fields, "schema");
	request.requestId = requireJsonField(fields, "request_id");
	request.responseJson = requireJsonField(fields, "response_json");
	request.adapterMode = requireJsonField(fields, "adapter_mode");
	request.readAlignmentAbi = requireJsonField(fields, "read_alignment_abi");
	request.outputMode = requireJsonField(fields, "output_mode");
	request.cudaExecutionMode = requireJsonField(fields, "cuda_execution_mode");
	request.options.backend = requireJsonField(fields, "backend");
	request.options.device = parseWorkerInt(requireJsonField(fields, "device"), "device");
	request.options.batchFixturesFile = requireJsonField(fields, "batch_fixtures_file");
	request.options.batchOutputDir = requireJsonField(fields, "batch_output_dir");
	request.options.batchJsonOutput = requireJsonField(fields, "batch_json_output");
	request.options.allowHeterogeneousBatch =
	    parseWorkerBool(requireJsonField(fields, "allow_heterogeneous_batch"),
	                    "allow_heterogeneous_batch");
	request.options.cudaPersistentArena =
	    parseWorkerBool(requireJsonField(fields, "cuda_persistent_arena"),
	                    "cuda_persistent_arena");
	request.options.cudaPersistentBulkOutput =
	    parseWorkerBool(requireJsonField(fields, "cuda_persistent_bulk_output"),
	                    "cuda_persistent_bulk_output");
	request.options.emitPreDivergenceChains =
	    parseWorkerBool(requireJsonField(fields, "emit_pre_divergence_chains"),
	                    "emit_pre_divergence_chains");
	request.options.warmupRuns =
	    parseWorkerUInt32(requireJsonField(fields, "warmup_runs"), "warmup_runs");
	request.options.benchmarkRuns =
	    parseWorkerUInt32(requireJsonField(fields, "benchmark_runs"), "benchmark_runs");

	std::string memoryBudget = optionalJsonField(fields, "memory_budget_bytes");
	if (!memoryBudget.empty() && memoryBudget != "null")
	{
		request.options.hasMemoryBudget = true;
		request.options.memoryBudgetBytes = parseWorkerUnsigned(memoryBudget,
		                                                        "memory_budget_bytes");
	}
	std::string expectedFixtureCount = optionalJsonField(fields, "expected_fixture_count");
	if (!expectedFixtureCount.empty() && expectedFixtureCount != "null")
	{
		request.hasExpectedFixtureCount = true;
		request.expectedFixtureCount =
		    static_cast<size_t>(parseWorkerUnsigned(expectedFixtureCount,
		                                            "expected_fixture_count"));
	}
	return request;
}

std::vector<ReadAlignmentWorkerRequest> loadReadAlignmentWorkerRequests(
    const Options& options)
{
	std::vector<ReadAlignmentWorkerRequest> requests;
	if (!options.workerRequestJson.empty())
	{
		requests.push_back(parseReadAlignmentWorkerRequestObject(
		    readTextFile(options.workerRequestJson)));
		return requests;
	}

	std::ifstream input(options.workerRequestsJsonl);
	if (!input)
	{
		throw std::runtime_error("cannot read read-alignment worker requests JSONL: " +
		                         options.workerRequestsJsonl);
	}
	std::string line;
	size_t lineNumber = 0;
	while (std::getline(input, line))
	{
		++lineNumber;
		std::string stripped = trim(line);
		if (stripped.empty()) continue;
		try
		{
			requests.push_back(parseReadAlignmentWorkerRequestObject(stripped));
		}
		catch (const std::exception& exc)
		{
			throw std::runtime_error(options.workerRequestsJsonl + ":" +
			                         std::to_string(lineNumber) + ": " + exc.what());
		}
	}
	if (requests.size() < 2)
	{
		throw std::runtime_error(
		    "--worker-requests-jsonl proof mode requires at least two requests");
	}
	return requests;
}

void validateReadAlignmentWorkerRequest(const ReadAlignmentWorkerRequest& request)
{
	if (request.schema != "cuflye-read-alignment-worker-request-v0")
	{
		throw std::runtime_error("unsupported read-alignment worker request schema");
	}
	if (request.adapterMode != "read-alignment-predivergence-batch-v0")
	{
		throw std::runtime_error("unsupported read-alignment worker adapter_mode");
	}
	if (request.readAlignmentAbi != "read-alignment-v1")
	{
		throw std::runtime_error("unsupported read-alignment worker read_alignment_abi");
	}
	if (request.outputMode != "pre-divergence-chains")
	{
		throw std::runtime_error("unsupported read-alignment worker output_mode");
	}
	if (request.options.backend != "cuda")
	{
		throw std::runtime_error("unsupported read-alignment worker backend");
	}
	if (request.cudaExecutionMode != "persistent-arena-bulk-output")
	{
		throw std::runtime_error("unsupported read-alignment worker cuda_execution_mode");
	}
	if (!request.options.allowHeterogeneousBatch)
	{
		throw std::runtime_error("read-alignment worker requires heterogeneous batch support");
	}
	if (!request.options.cudaPersistentArena ||
	    !request.options.cudaPersistentBulkOutput)
	{
		throw std::runtime_error("read-alignment worker requires persistent bulk CUDA arena");
	}
	if (!request.options.emitPreDivergenceChains)
	{
		throw std::runtime_error("read-alignment worker requires pre-divergence output mode");
	}
	if (request.options.benchmarkRuns == 0)
	{
		throw std::runtime_error("read-alignment worker benchmark_runs must be greater than zero");
	}
}

void validateReadAlignmentWorkerRequestSet(
    const std::vector<ReadAlignmentWorkerRequest>& requests)
{
	if (requests.empty()) throw std::runtime_error("read-alignment worker request set is empty");
	int device = requests.front().options.device;
	for (const auto& request : requests)
	{
		if (request.options.device != device)
		{
			throw std::runtime_error(
			    "read-alignment worker requires all requests to use one CUDA device");
		}
	}
}

std::string buildReadAlignmentWorkerResponseJson(
    const ReadAlignmentWorkerRequest& request, const ReadAlignmentWorkerResult& result,
    const ReadAlignmentSessionCache& cache, size_t requestOrdinal,
    bool workerContextWarm, double workerContextSetupMs, double workerUptimeMs,
    double requestTotalMs)
{
	double timedBackendTotal = result.summary.benchmarkMeanTotalMs *
	                           static_cast<double>(request.options.benchmarkRuns);
	double workerOverhead = std::max(0.0, requestTotalMs - timedBackendTotal);
	std::ostringstream json;
	json << std::fixed << std::setprecision(6);
	json << "{\n"
	     << "  \"schema\": \"cuflye-read-alignment-worker-response-v0\",\n"
	     << "  \"request_id\": \"" << jsonEscape(request.requestId) << "\",\n"
	     << "  \"status\": \"ok\",\n"
	     << "  \"request_ordinal\": " << requestOrdinal << ",\n"
	     << "  \"worker_cuda_context_warm\": "
	     << (workerContextWarm ? "true" : "false") << ",\n"
	     << "  \"worker_context_setup_ms\": " << workerContextSetupMs << ",\n"
	     << "  \"worker_device_arena_enabled\": true,\n"
	     << "  \"worker_device_arena_cache_hit\": "
	     << (result.arenaCacheHit ? "true" : "false") << ",\n"
	     << "  \"worker_device_arena_created\": "
	     << (result.arenaCacheCreated ? "true" : "false") << ",\n"
	     << "  \"worker_device_arena_capacity_bytes\": "
	     << (cache.initialized ? cache.arena.requiredBytes : 0) << ",\n"
	     << "  \"adapter_mode\": \"read-alignment-predivergence-batch-v0\",\n"
	     << "  \"read_alignment_abi\": \"read-alignment-v1\",\n"
	     << "  \"output_mode\": \"pre-divergence-chains\",\n"
	     << "  \"cuda_execution_mode\": \""
	     << jsonEscape(result.summary.cudaExecutionMode) << "\",\n"
	     << "  \"fixture_count\": " << result.fixtureCount << ",\n"
	     << "  \"output_records\": " << result.outputRecords << ",\n"
	     << "  \"batch_json_output\": \""
	     << jsonEscape(request.options.batchJsonOutput) << "\",\n"
	     << "  \"batch_output_dir\": \""
	     << jsonEscape(request.options.batchOutputDir) << "\",\n"
	     << "  \"timing_ms\": {\n"
	     << "    \"worker_uptime\": " << workerUptimeMs << ",\n"
	     << "    \"request_total\": " << requestTotalMs << ",\n"
	     << "    \"backend_mean_total_before_json\": "
	     << result.summary.benchmarkMeanTotalMs << ",\n"
	     << "    \"backend_timed_total_before_json\": " << timedBackendTotal << ",\n"
	     << "    \"worker_overhead\": " << workerOverhead << ",\n"
	     << "    \"one_time_arena_setup\": " << result.summary.oneTimeSetupMs << ",\n"
	     << "    \"one_time_arena_device_allocation\": "
	     << result.summary.oneTimeDeviceAllocationMs << ",\n"
	     << "    \"one_time_arena_host_to_device\": "
	     << result.summary.oneTimeHostToDeviceMs << ",\n"
	     << "    \"one_time_arena_total\": " << result.summary.oneTimeTotalMs << ",\n"
	     << "    \"write_output\": " << result.summary.writeMs << ",\n"
	     << "    \"kernel\": " << result.summary.kernelMs << ",\n"
	     << "    \"device_to_host\": " << result.summary.deviceToHostMs << "\n"
	     << "  }\n"
	     << "}\n";
	return json.str();
}

std::string buildReadAlignmentWorkerErrorJson(
    const ReadAlignmentWorkerRequest& request, size_t requestOrdinal,
    const std::string& message)
{
	std::ostringstream json;
	json << "{\n"
	     << "  \"schema\": \"cuflye-read-alignment-worker-response-v0\",\n"
	     << "  \"request_id\": \"" << jsonEscape(request.requestId) << "\",\n"
	     << "  \"status\": \"error\",\n"
	     << "  \"request_ordinal\": " << requestOrdinal << ",\n"
	     << "  \"error_code\": \"request-failed\",\n"
	     << "  \"error_message\": \"" << jsonEscape(message) << "\",\n"
	     << "  \"cuda_error_code\": null,\n"
	     << "  \"cuda_error_name\": null,\n"
	     << "  \"cuda_error_text\": null\n"
	     << "}\n";
	return json.str();
}

void emitReadAlignmentWorkerResponse(const std::string& path, const std::string& response)
{
	writeTextFile(path, response);
	std::cout << response;
}

bool executeReadAlignmentWorkerRequest(
    const ReadAlignmentWorkerRequest& request, size_t requestOrdinal,
    bool workerContextWarm, double workerContextSetupMs, Clock::time_point workerStart,
    ReadAlignmentSessionCache& cache)
{
	auto requestStart = Clock::now();
	try
	{
		validateReadAlignmentWorkerRequest(request);
		ReadAlignmentWorkerResult result;
		if (sameSessionArenaRequest(cache, request))
		{
			result.arenaCacheHit = true;
		}
		else
		{
			cache.fixtures = loadReadAlignmentWorkerFixtures(request);
			CudaPersistentArena arena = buildCudaPersistentArena(request.options,
			                                                     cache.fixtures);
			cache.arena = std::move(arena);
			cache.initialized = true;
			cache.batchFixturesFile = request.options.batchFixturesFile;
			cache.device = request.options.device;
			cache.hasMemoryBudget = request.options.hasMemoryBudget;
			cache.memoryBudgetBytes = request.options.memoryBudgetBytes;
			cache.emitPreDivergenceChains = request.options.emitPreDivergenceChains;
			cache.allowHeterogeneousBatch = request.options.allowHeterogeneousBatch;
			result.arenaCacheCreated = true;
		}

		std::vector<std::vector<OutputSegment>> segmentsByFixture;
		RunSummary summary = runCudaPersistentArenaBenchmarkWithExistingArena(
		    request.options, cache.arena, segmentsByFixture);

		auto writeStart = Clock::now();
		std::vector<BatchFixtureOutput> outputs =
		    writeBatchReadAlignments(request.options, cache.fixtures, segmentsByFixture);
		auto writeEnd = Clock::now();
		summary.writeMs = elapsedMs(writeStart, writeEnd);
		writeBatchJsonSummary(request.options.batchJsonOutput, request.options,
		                      summary, outputs);

		result.summary = summary;
		result.fixtureCount = outputs.size();
		result.outputRecords = summary.outputRecords;
		double requestTotalMs = elapsedMs(requestStart, Clock::now());
		double workerUptimeMs = elapsedMs(workerStart, Clock::now());
		std::string response = buildReadAlignmentWorkerResponseJson(
		    request, result, cache, requestOrdinal, workerContextWarm,
		    workerContextSetupMs, workerUptimeMs, requestTotalMs);
		emitReadAlignmentWorkerResponse(request.responseJson, response);
		return true;
	}
	catch (const std::exception& exc)
	{
		std::string response =
		    buildReadAlignmentWorkerErrorJson(request, requestOrdinal, exc.what());
		emitReadAlignmentWorkerResponse(request.responseJson, response);
		return false;
	}
}

std::string sessionInboxDir(const Options& options)
{
	return joinPath(options.workerSessionDir, "inbox");
}

std::string sessionProcessingDir(const Options& options)
{
	return joinPath(options.workerSessionDir, "processing");
}

std::string sessionDoneDir(const Options& options)
{
	return joinPath(options.workerSessionDir, "done");
}

bool hasSuffix(const std::string& value, const std::string& suffix)
{
	return value.size() >= suffix.size() &&
	       value.compare(value.size() - suffix.size(), suffix.size(), suffix) == 0;
}

std::vector<std::string> listSessionReadyFiles(const std::string& inbox)
{
	std::vector<std::string> readyFiles;
	std::unique_ptr<DIR, int (*)(DIR*)> dir(::opendir(inbox.c_str()), ::closedir);
	if (!dir)
	{
		if (errno == ENOENT) return readyFiles;
		throw std::runtime_error("cannot read worker session inbox: " + inbox +
		                         ": " + std::strerror(errno));
	}
	while (dirent* entry = ::readdir(dir.get()))
	{
		std::string name = entry->d_name;
		if (name == "." || name == "..") continue;
		if (!hasSuffix(name, ".ready")) continue;
		readyFiles.push_back(joinPath(inbox, name));
	}
	std::sort(readyFiles.begin(), readyFiles.end());
	return readyFiles;
}

void renameFile(const std::string& from, const std::string& to)
{
	ensureParentDirectory(to);
	if (::rename(from.c_str(), to.c_str()) != 0)
	{
		throw std::runtime_error("cannot rename " + from + " to " + to +
		                         ": " + std::strerror(errno));
	}
}

double initializeReadAlignmentWorkerContext(const Options& options,
                                            std::string& deviceName,
                                            size_t& freeBytes,
                                            size_t& totalBytes)
{
	auto contextStart = Clock::now();
	cuflye::cuda_raii::checkCuda(cudaSetDevice(options.device), "set CUDA worker device");
	cudaDeviceProp props{};
	cuflye::cuda_raii::checkCuda(cudaGetDeviceProperties(&props, options.device),
	                             "get CUDA worker device properties");
	deviceName = props.name;
	cuflye::cuda_raii::checkCuda(cudaMemGetInfo(&freeBytes, &totalBytes),
	                             "query CUDA worker memory");
	return elapsedMs(contextStart, Clock::now());
}

void writeReadAlignmentWorkerSessionStateJson(
    const std::string& path, const Options& options, const std::string& status,
    size_t processedRequests, double workerContextSetupMs,
    const std::string& deviceName, size_t freeBytes, size_t totalBytes,
    const ReadAlignmentSessionCache& cache)
{
	std::ostringstream json;
	json << std::fixed << std::setprecision(6);
	json << "{\n"
	     << "  \"schema\": \"cuflye-read-alignment-worker-session-v0\",\n"
	     << "  \"status\": \"" << jsonEscape(status) << "\",\n"
	     << "  \"worker_session_dir\": \"" << jsonEscape(options.workerSessionDir) << "\",\n"
	     << "  \"worker_session_max_requests\": "
	     << options.workerSessionMaxRequests << ",\n"
	     << "  \"worker_session_processed_requests\": "
	     << processedRequests << ",\n"
	     << "  \"worker_session_poll_ms\": " << options.workerSessionPollMs << ",\n"
	     << "  \"worker_session_timeout_ms\": "
	     << options.workerSessionTimeoutMs << ",\n"
	     << "  \"worker_context_setup_ms\": " << workerContextSetupMs << ",\n"
	     << "  \"worker_device_arena_enabled\": true,\n"
	     << "  \"worker_device_arena_initialized\": "
	     << (cache.initialized ? "true" : "false") << ",\n"
	     << "  \"worker_device_arena_capacity_bytes\": "
	     << (cache.initialized ? cache.arena.requiredBytes : 0) << ",\n"
	     << "  \"device\": " << options.device << ",\n"
	     << "  \"device_name\": \"" << jsonEscape(deviceName) << "\",\n"
	     << "  \"free_bytes\": " << freeBytes << ",\n"
	     << "  \"total_bytes\": " << totalBytes << ",\n"
	     << "  \"pid\": " << static_cast<long long>(::getpid()) << "\n"
	     << "}\n";
	writeTextFile(path, json.str());
}

int runReadAlignmentWorkerSessionMain(const Options& cliOptions)
{
	ensureDirectory(cliOptions.workerSessionDir);
	ensureDirectory(sessionInboxDir(cliOptions));
	ensureDirectory(sessionProcessingDir(cliOptions));
	ensureDirectory(sessionDoneDir(cliOptions));

	ReadAlignmentSessionCache cache;
	auto workerStart = Clock::now();
	std::string deviceName;
	size_t freeBytes = 0;
	size_t totalBytes = 0;
	double workerContextSetupMs = initializeReadAlignmentWorkerContext(
	    cliOptions, deviceName, freeBytes, totalBytes);
	writeReadAlignmentWorkerSessionStateJson(
	    joinPath(cliOptions.workerSessionDir, "session-ready.json"),
	    cliOptions, "ready", 0, workerContextSetupMs, deviceName,
	    freeBytes, totalBytes, cache);

	size_t processedRequests = 0;
	auto idleStart = Clock::now();
	while (processedRequests < cliOptions.workerSessionMaxRequests)
	{
		std::vector<std::string> readyFiles =
		    listSessionReadyFiles(sessionInboxDir(cliOptions));
		if (readyFiles.empty())
		{
			double idleMs = elapsedMs(idleStart, Clock::now());
			if (idleMs > static_cast<double>(cliOptions.workerSessionTimeoutMs))
			{
				writeReadAlignmentWorkerSessionStateJson(
				    joinPath(cliOptions.workerSessionDir, "session-error.json"),
				    cliOptions, "timeout", processedRequests, workerContextSetupMs,
				    deviceName, freeBytes, totalBytes, cache);
				return 1;
			}
			std::this_thread::sleep_for(
			    std::chrono::milliseconds(cliOptions.workerSessionPollMs));
			continue;
		}

		idleStart = Clock::now();
		std::string readyPath = readyFiles.front();
		std::string readyName = baseName(readyPath);
		std::string processingPath =
		    joinPath(sessionProcessingDir(cliOptions), readyName + ".processing");
		std::string donePath = joinPath(sessionDoneDir(cliOptions), readyName + ".done");
		renameFile(readyPath, processingPath);
		std::string requestJsonPath = trim(readTextFile(processingPath));
		if (requestJsonPath.empty())
		{
			writeTextFile(donePath, "status=error\nerror=empty request path\n");
			writeReadAlignmentWorkerSessionStateJson(
			    joinPath(cliOptions.workerSessionDir, "session-error.json"),
			    cliOptions, "error", processedRequests, workerContextSetupMs,
			    deviceName, freeBytes, totalBytes, cache);
			return 1;
		}

		ReadAlignmentWorkerRequest request;
		try
		{
			request = parseReadAlignmentWorkerRequestObject(readTextFile(requestJsonPath));
		}
		catch (const std::exception& exc)
		{
			writeTextFile(donePath, "status=error\nrequest_json=" +
			              requestJsonPath + "\nerror=" + exc.what() + "\n");
			writeReadAlignmentWorkerSessionStateJson(
			    joinPath(cliOptions.workerSessionDir, "session-error.json"),
			    cliOptions, "error", processedRequests, workerContextSetupMs,
			    deviceName, freeBytes, totalBytes, cache);
			return 1;
		}

		++processedRequests;
		if (request.options.device != cliOptions.device)
		{
			std::string message =
			    "read-alignment worker session request device does not match session device";
			emitReadAlignmentWorkerResponse(
			    request.responseJson,
			    buildReadAlignmentWorkerErrorJson(request, processedRequests, message));
			writeTextFile(donePath, "status=error\nrequest_json=" +
			              requestJsonPath + "\nerror=" + message + "\n");
			writeReadAlignmentWorkerSessionStateJson(
			    joinPath(cliOptions.workerSessionDir, "session-error.json"),
			    cliOptions, "error", processedRequests, workerContextSetupMs,
			    deviceName, freeBytes, totalBytes, cache);
			return 1;
		}

		bool ok = executeReadAlignmentWorkerRequest(
		    request, processedRequests, true, workerContextSetupMs, workerStart, cache);
		writeTextFile(donePath, std::string("status=") + (ok ? "ok" : "error") +
		              "\nrequest_json=" + requestJsonPath + "\n");
		if (!ok)
		{
			writeReadAlignmentWorkerSessionStateJson(
			    joinPath(cliOptions.workerSessionDir, "session-error.json"),
			    cliOptions, "error", processedRequests, workerContextSetupMs,
			    deviceName, freeBytes, totalBytes, cache);
			return 1;
		}
	}

	writeReadAlignmentWorkerSessionStateJson(
	    joinPath(cliOptions.workerSessionDir, "session-complete.json"),
	    cliOptions, "complete", processedRequests, workerContextSetupMs,
	    deviceName, freeBytes, totalBytes, cache);
	return 0;
}

int runReadAlignmentWorkerMain(const Options& cliOptions)
{
	if (!cliOptions.workerSessionDir.empty())
	{
		return runReadAlignmentWorkerSessionMain(cliOptions);
	}

	std::vector<ReadAlignmentWorkerRequest> requests =
	    loadReadAlignmentWorkerRequests(cliOptions);
	validateReadAlignmentWorkerRequestSet(requests);

	ReadAlignmentSessionCache cache;
	auto workerStart = Clock::now();
	std::string deviceName;
	size_t freeBytes = 0;
	size_t totalBytes = 0;
	double workerContextSetupMs = initializeReadAlignmentWorkerContext(
	    requests.front().options, deviceName, freeBytes, totalBytes);
	(void)deviceName;
	(void)freeBytes;
	(void)totalBytes;

	for (size_t index = 0; index < requests.size(); ++index)
	{
		size_t requestOrdinal = index + 1;
		bool workerContextWarm = requestOrdinal > 1;
		bool ok = executeReadAlignmentWorkerRequest(
		    requests[index], requestOrdinal, workerContextWarm,
		    workerContextSetupMs, workerStart, cache);
		if (!ok) return 1;
	}
	return 0;
}

void parseArgs(int argc, char** argv, Options& options)
{
	for (int index = 1; index < argc; ++index)
	{
		std::string arg = argv[index];
		auto nextValue = [&]() -> std::string
		{
			if (index + 1 >= argc)
			{
				throw std::runtime_error("missing value for " + arg);
			}
			return argv[++index];
		};
		if (arg == "--fixture-dir")
			options.fixtureDir = nextValue();
		else if (arg == "--output-tsv")
			options.outputTsv = nextValue();
		else if (arg == "--json-output")
			options.jsonOutput = nextValue();
		else if (arg == "--batch-fixtures-file")
			options.batchFixturesFile = nextValue();
		else if (arg == "--batch-output-dir")
			options.batchOutputDir = nextValue();
		else if (arg == "--batch-json-output")
			options.batchJsonOutput = nextValue();
		else if (arg == "--worker-request-json")
			options.workerRequestJson = nextValue();
		else if (arg == "--worker-requests-jsonl")
			options.workerRequestsJsonl = nextValue();
		else if (arg == "--worker-session-dir")
			options.workerSessionDir = nextValue();
		else if (arg == "--allow-heterogeneous-batch")
			options.allowHeterogeneousBatch = true;
		else if (arg == "--cuda-persistent-arena")
			options.cudaPersistentArena = true;
		else if (arg == "--cuda-persistent-bulk-output")
			options.cudaPersistentBulkOutput = true;
		else if (arg == "--emit-pre-divergence-chains")
			options.emitPreDivergenceChains = true;
		else if (arg == "--backend")
			options.backend = nextValue();
		else if (arg == "--device")
			options.device = std::stoi(nextValue());
		else if (arg == "--warmup-runs")
		{
			options.warmupRuns = static_cast<uint32_t>(std::stoul(nextValue()));
		}
		else if (arg == "--benchmark-runs")
		{
			options.benchmarkRuns = static_cast<uint32_t>(std::stoul(nextValue()));
		}
		else if (arg == "--replicate-fixture")
		{
			options.replicateFixture = static_cast<uint32_t>(std::stoul(nextValue()));
		}
		else if (arg == "--memory-budget-bytes")
		{
			options.hasMemoryBudget = true;
			options.memoryBudgetBytes = std::stoull(nextValue());
		}
		else if (arg == "--worker-session-max-requests")
		{
			options.workerSessionMaxRequests =
			    parseWorkerUInt32(nextValue(), "--worker-session-max-requests");
		}
		else if (arg == "--worker-session-poll-ms")
		{
			options.workerSessionPollMs =
			    parseWorkerUInt32(nextValue(), "--worker-session-poll-ms");
		}
		else if (arg == "--worker-session-timeout-ms")
		{
			options.workerSessionTimeoutMs =
			    parseWorkerUInt32(nextValue(), "--worker-session-timeout-ms");
		}
		else if (arg == "-h" || arg == "--help")
		{
			std::cout << "Usage: cuflye-cuda-read-alignment-chain-replay "
			          << "--fixture-dir DIR --output-tsv PATH --json-output PATH "
			          << "[--backend cpu|cuda] [--device ID] "
			          << "[--warmup-runs N] [--benchmark-runs N] "
			          << "[--replicate-fixture N] "
			          << "[--emit-pre-divergence-chains] "
			          << "[--memory-budget-bytes BYTES]\n"
			          << "Batch mode: cuflye-cuda-read-alignment-chain-replay "
			          << "--batch-fixtures-file FILE --batch-output-dir DIR "
			          << "--batch-json-output PATH [--backend cpu|cuda] "
			          << "[--device ID] [--warmup-runs N] [--benchmark-runs N] "
			          << "[--allow-heterogeneous-batch] [--cuda-persistent-arena] "
			          << "[--cuda-persistent-bulk-output] "
			          << "[--emit-pre-divergence-chains] "
			          << "[--memory-budget-bytes BYTES]\n"
			          << "Worker mode: cuflye-cuda-read-alignment-chain-replay "
			          << "--worker-request-json PATH "
			          << "or --worker-requests-jsonl PATH "
			          << "or --worker-session-dir DIR "
			          << "[--device ID] [--worker-session-max-requests N] "
			          << "[--worker-session-poll-ms N] "
			          << "[--worker-session-timeout-ms N]\n";
			std::exit(0);
		}
		else
		{
			throw std::runtime_error("unknown option: " + arg);
		}
	}

	bool batchMode = !options.batchFixturesFile.empty() || !options.batchOutputDir.empty() ||
	                 !options.batchJsonOutput.empty();
	bool workerMode = !options.workerRequestJson.empty() ||
	                  !options.workerRequestsJsonl.empty() ||
	                  !options.workerSessionDir.empty();
	if (workerMode)
	{
		int workerInputs = 0;
		if (!options.workerRequestJson.empty()) ++workerInputs;
		if (!options.workerRequestsJsonl.empty()) ++workerInputs;
		if (!options.workerSessionDir.empty()) ++workerInputs;
		if (workerInputs != 1)
		{
			throw std::runtime_error("set exactly one worker request input");
		}
		if (batchMode || !options.fixtureDir.empty() || !options.outputTsv.empty() ||
		    !options.jsonOutput.empty())
		{
			throw std::runtime_error("worker mode cannot be combined with direct replay mode");
		}
	}
	else if (batchMode)
	{
		if (options.batchFixturesFile.empty())
		{
			throw std::runtime_error("--batch-fixtures-file is required in batch mode");
		}
		if (options.batchOutputDir.empty())
		{
			throw std::runtime_error("--batch-output-dir is required in batch mode");
		}
		if (options.batchJsonOutput.empty())
		{
			throw std::runtime_error("--batch-json-output is required in batch mode");
		}
		if (!options.fixtureDir.empty() || !options.outputTsv.empty() ||
		    !options.jsonOutput.empty())
		{
			throw std::runtime_error(
			    "single-fixture output options are not supported in batch mode");
		}
		if (options.replicateFixture != 1)
		{
			throw std::runtime_error("--replicate-fixture is not supported in batch mode");
		}
		if (options.cudaPersistentArena && options.backend != "cuda")
		{
			throw std::runtime_error("--cuda-persistent-arena requires --backend cuda");
		}
		if (options.cudaPersistentBulkOutput && !options.cudaPersistentArena)
		{
			throw std::runtime_error(
			    "--cuda-persistent-bulk-output requires --cuda-persistent-arena");
		}
	}
	else
	{
		if (options.allowHeterogeneousBatch)
		{
			throw std::runtime_error("--allow-heterogeneous-batch is only supported in batch mode");
		}
		if (options.cudaPersistentArena)
		{
			throw std::runtime_error("--cuda-persistent-arena is only supported in batch mode");
		}
		if (options.cudaPersistentBulkOutput)
		{
			throw std::runtime_error(
			    "--cuda-persistent-bulk-output is only supported in batch mode");
		}
		if (options.fixtureDir.empty()) throw std::runtime_error("--fixture-dir is required");
		if (options.outputTsv.empty()) throw std::runtime_error("--output-tsv is required");
		if (options.jsonOutput.empty()) throw std::runtime_error("--json-output is required");
	}
	if (options.backend != "cpu" && options.backend != "cuda")
	{
		throw std::runtime_error("--backend must be cpu or cuda");
	}
	if (options.backend == "cpu" && options.hasMemoryBudget)
	{
		throw std::runtime_error("--memory-budget-bytes is only supported for cuda backend");
	}
	if (options.benchmarkRuns == 0)
	{
		throw std::runtime_error("--benchmark-runs must be greater than zero");
	}
	if (options.replicateFixture == 0)
	{
		throw std::runtime_error("--replicate-fixture must be greater than zero");
	}
	if (!options.workerSessionDir.empty() && options.workerSessionMaxRequests == 0)
	{
		throw std::runtime_error("--worker-session-max-requests must be greater than zero");
	}
	if (!options.workerSessionDir.empty() && options.workerSessionPollMs == 0)
	{
		throw std::runtime_error("--worker-session-poll-ms must be greater than zero");
	}
	if (!options.workerSessionDir.empty() && options.workerSessionTimeoutMs == 0)
	{
		throw std::runtime_error("--worker-session-timeout-ms must be greater than zero");
	}
}
} // namespace

int main(int argc, char** argv)
{
	try
	{
		Options options;
		parseArgs(argc, argv, options);
		if (!options.workerRequestJson.empty() ||
		    !options.workerRequestsJsonl.empty() ||
		    !options.workerSessionDir.empty())
		{
			return runReadAlignmentWorkerMain(options);
		}
		if (!options.batchFixturesFile.empty())
		{
			std::vector<LoadedFixture> fixtures = loadBatchFixtures(
			    options.batchFixturesFile, options.allowHeterogeneousBatch,
			    !options.emitPreDivergenceChains);
			std::vector<std::vector<OutputSegment>> segmentsByFixture;
			RunSummary summary = runBatchBenchmark(options, fixtures, segmentsByFixture);

			auto writeStart = Clock::now();
			std::vector<BatchFixtureOutput> outputs =
			    writeBatchReadAlignments(options, fixtures, segmentsByFixture);
			auto writeEnd = Clock::now();
			summary.writeMs = elapsedMs(writeStart, writeEnd);
			writeBatchJsonSummary(options.batchJsonOutput, options, summary, outputs);

			std::cout << "cuFlye read-alignment chain replay batch: ok\n"
			          << "  backend: " << summary.backend << "\n"
			          << "  cuda execution mode: " << summary.cudaExecutionMode << "\n"
			          << "  fixture count: " << outputs.size() << "\n"
			          << "  shape groups: " << summary.shapeGroups << "\n";
			if (summary.inputRecords == 0)
			{
				std::cout << "  input records per fixture: heterogeneous\n";
			}
			else
			{
				std::cout << "  input records per fixture: " << summary.inputRecords << "\n";
			}
			std::cout << "  total input records: " << summary.totalInputRecords << "\n"
			          << "  output records: " << summary.outputRecords << "\n"
			          << "  mean total before JSON: " << summary.benchmarkMeanTotalMs << " ms\n";
			if (summary.cudaExecutionMode == "persistent-arena")
			{
				std::cout << "  one-time arena setup: " << summary.oneTimeTotalMs << " ms\n";
			}
			return 0;
		}

		LoadedFixture fixture =
		    loadFixture(options.fixtureDir, !options.emitPreDivergenceChains);
		std::vector<OutputSegment> segments;
		RunSummary summary = runBenchmark(options, fixture, segments);

		auto writeStart = Clock::now();
		writeReadAlignment(options.outputTsv, fixture.overlaps, segments);
		auto writeEnd = Clock::now();
		summary.writeMs = elapsedMs(writeStart, writeEnd);
		writeJsonSummary(options.jsonOutput, options, fixture.manifest, summary);

		std::cout << "cuFlye read-alignment chain replay: ok\n"
		          << "  backend: " << summary.backend << "\n"
		          << "  batch size: " << summary.batchSize << "\n"
		          << "  input records: " << summary.inputRecords << "\n"
		          << "  total input records: " << summary.totalInputRecords << "\n"
		          << "  output records: " << summary.outputRecords << "\n"
		          << "  mean total before JSON: " << summary.benchmarkMeanTotalMs << " ms\n";
		return 0;
	}
	catch (const std::exception& exc)
	{
		std::cerr << "error: " << exc.what() << "\n";
		return 1;
	}
}
