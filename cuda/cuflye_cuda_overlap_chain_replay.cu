// SPDX-License-Identifier: BSD-3-Clause

#include <cuda_runtime_api.h>

#include "cuflye_cuda_raii.hpp"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cctype>
#include <climits>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include <sys/stat.h>
#include <sys/types.h>

namespace
{
using Clock = std::chrono::steady_clock;
static const int OVERLAP_CHAIN_REDUCE_THREADS = 128;

struct CandidateRecord
{
	int64_t queryId;
	int32_t queryPos;
	uint64_t kmer;
	int64_t targetId;
	int32_t targetPos;
	char targetStrand;
	char padding[7];
};

struct TargetGroup
{
	int64_t targetId;
	int32_t targetLen;
	uint32_t start;
	uint32_t count;
	int32_t minCur;
	int32_t maxCur;
	int32_t minExt;
	int32_t maxExt;
	int32_t extSorted;
	int32_t paramsIndex;
};

struct DeviceParams
{
	int64_t queryId;
	int32_t queryLen;
	int32_t kmerSize;
	float minKmerSurvivalRate;
	float largeGapPenalty;
	float smallGapPenalty;
	int32_t gapJumpThreshold;
	int32_t maxGap;
	int32_t maximumJump;
	int32_t minimumOverlap;
	int32_t maximumOverhang;
	int32_t checkOverhang;
	int32_t forceLocal;
};

struct DeviceOverlap
{
	int64_t curId;
	int32_t curBegin;
	int32_t curEnd;
	int32_t curLen;
	int64_t extId;
	int32_t extBegin;
	int32_t extEnd;
	int32_t extLen;
	int32_t score;
	int32_t chainLength;
	int32_t valid;
	int32_t padding;
};

struct HostOverlap
{
	int64_t curId;
	int32_t curBegin;
	int32_t curEnd;
	int32_t curLen;
	int64_t extId;
	int32_t extBegin;
	int32_t extEnd;
	int32_t extLen;
	int32_t score;
	float seqDivergence;
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
	std::string backend = "cuda";
	std::string cudaKernelMode = "serial";
	std::string batchExecution = "per-fixture";
	int device = 0;
	uint32_t warmupRuns = 0;
	uint32_t benchmarkRuns = 1;
	bool hasMemoryBudget = false;
	unsigned long long memoryBudgetBytes = 0;
};

struct FixtureFiles
{
	std::string candidates = "candidates.tsv";
	std::string filteredPositions = "filtered-positions.tsv";
	std::string targets = "targets.tsv";
	std::string oracleOverlaps = "oracle.overlaps.tsv";
};

struct ReplayParameters
{
	bool forceLocal = false;
	int32_t maxOverlaps = 0;
	int32_t kmerSize = 0;
	float minKmerSurvivalRate = 0.0f;
	float largeGapPenalty = 0.0f;
	float smallGapPenalty = 0.0f;
	int32_t gapJumpThreshold = 0;
	int32_t maxGap = 0;
	int32_t maximumJump = 0;
	int32_t minimumOverlap = 0;
	int32_t maximumOverhang = 0;
	bool checkOverhang = false;
	bool keepAlignment = false;
	bool onlyMaxExt = false;
	bool nuclAlignment = false;
	bool partitionBadMappings = false;
	bool useHpc = false;
	float maxDivergence = 0.0f;
	float sampleRate = 1.0f;
};

struct FixtureManifest
{
	int64_t queryId = 0;
	int32_t queryLength = 0;
	uint64_t expectedCandidateRecords = 0;
	uint64_t expectedTargetRecords = 0;
	uint64_t expectedOracleOverlapRecords = 0;
	FixtureFiles files;
	ReplayParameters params;
};

struct CudaRunSummary
{
	std::string backend = "cuda";
	std::string cudaKernelMode = "serial";
	double parseMs = 0.0;
	double setupMs = 0.0;
	double deviceAllocationMs = 0.0;
	double hostToDeviceMs = 0.0;
	double kernelMs = 0.0;
	double cpuChainMs = 0.0;
	double deviceToHostMs = 0.0;
	double finalizeMs = 0.0;
	double writeMs = 0.0;
	double totalBeforeJsonMs = 0.0;
	uint32_t warmupRuns = 0;
	uint32_t timedRuns = 1;
	double benchmarkMeanTotalMs = 0.0;
	double benchmarkMinTotalMs = 0.0;
	double benchmarkMaxTotalMs = 0.0;
	double benchmarkMeanCoreMs = 0.0;
	size_t arenaAllocations = 0;
	size_t arenaReuses = 0;
	size_t arenaCapacityBytes = 0;
	size_t kernelLaunches = 0;
	size_t requiredBytes = 0;
	size_t freeBytes = 0;
	size_t totalBytes = 0;
	size_t candidateRecords = 0;
	size_t targetGroups = 0;
	size_t filteredPositions = 0;
	size_t outputRecords = 0;
	std::string deviceName;
	int device = 0;
};

struct LoadedFixture
{
	std::string fixtureDir;
	std::string name;
	FixtureManifest manifest;
	std::vector<CandidateRecord> candidates;
	std::vector<int32_t> filteredPositions;
	std::vector<TargetGroup> groups;
};

struct CudaOverlapArena
{
	cuflye::cuda_raii::DeviceBuffer<CandidateRecord> candidates;
	cuflye::cuda_raii::DeviceBuffer<TargetGroup> groups;
	cuflye::cuda_raii::DeviceBuffer<DeviceParams> params;
	cuflye::cuda_raii::DeviceBuffer<int32_t> filtered;
	cuflye::cuda_raii::DeviceBuffer<int32_t> scores;
	cuflye::cuda_raii::DeviceBuffer<int32_t> backtrack;
	cuflye::cuda_raii::DeviceBuffer<uint8_t> used;
	cuflye::cuda_raii::DeviceBuffer<DeviceOverlap> output;
	std::string deviceName;
	size_t freeBytes = 0;
	size_t totalBytes = 0;
	size_t allocations = 0;
	size_t reuses = 0;
	int device = 0;
	bool initialized = false;

	size_t capacityBytes() const
	{
		return candidates.bytes() + groups.bytes() + params.bytes() + filtered.bytes() +
			   scores.bytes() + backtrack.bytes() + used.bytes() + output.bytes();
	}
};

struct PackedBatchLayout
{
	std::vector<CandidateRecord> candidates;
	std::vector<TargetGroup> groups;
	std::vector<DeviceParams> params;
	std::vector<size_t> candidateOffsets;
	std::vector<size_t> groupOffsets;
	size_t totalFilteredPositions = 0;
};

struct BatchJsonProvenance
{
	std::string batchExecution = "per-fixture";
	size_t kernelLaunchesPerTimedRun = 0;
	size_t packedCandidateRecords = 0;
	size_t packedTargetGroups = 0;
	size_t packedParamRecords = 0;
	size_t packedFilteredPositions = 0;
};

struct PackedBatchRunResult
{
	double setupMs = 0.0;
	double parseMs = 0.0;
	double writeMs = 0.0;
	double meanTotalMs = 0.0;
	double minTotalMs = 0.0;
	double maxTotalMs = 0.0;
	double meanCoreMs = 0.0;
	size_t fixtureCount = 0;
	size_t outputRecords = 0;
	size_t arenaAllocations = 0;
	size_t arenaReuses = 0;
	size_t arenaCapacityBytes = 0;
	BatchJsonProvenance provenance;
};

struct OverlapWorkerRequest
{
	std::string schema;
	std::string requestId;
	std::string responseJson;
	std::string adapterMode;
	std::string overlapAbi;
	bool hasExpectedFixtureCount = false;
	size_t expectedFixtureCount = 0;
	Options options;
};

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
		std::string part = path.substr(index, slash == std::string::npos ?
									   std::string::npos : slash - index);
		if (!part.empty())
		{
			if (!current.empty() && current[current.size() - 1] != '/') current += "/";
			current += part;
			if (::mkdir(current.c_str(), 0775) != 0 && errno != EEXIST)
			{
				throw std::runtime_error("cannot create directory: " + current +
										 ": " + std::strerror(errno));
			}
		}
		if (slash == std::string::npos) break;
		index = slash + 1;
	}
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

bool isSpace(char ch)
{
	return std::isspace(static_cast<unsigned char>(ch)) != 0;
}

std::string trim(const std::string& text)
{
	size_t begin = 0;
	while (begin < text.size() && isSpace(text[begin])) ++begin;
	size_t end = text.size();
	while (end > begin && isSpace(text[end - 1])) --end;
	return text.substr(begin, end - begin);
}

void ensureParentDirectory(const std::string& path)
{
	size_t slash = path.find_last_of('/');
	if (slash == std::string::npos || slash == 0) return;
	ensureDirectory(path.substr(0, slash));
}

void writeTextFile(const std::string& path, const std::string& text)
{
	ensureParentDirectory(path);
	std::ofstream output(path);
	if (!output)
	{
		throw std::runtime_error("cannot write text file: " + path);
	}
	output << text;
}

void skipJsonWhitespace(const std::string& text, size_t& offset)
{
	while (offset < text.size() && isSpace(text[offset])) ++offset;
}

std::string parseJsonStringToken(const std::string& text, size_t& offset)
{
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
		throw std::runtime_error("nested JSON values are not supported by overlap worker v0");
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
		throw std::runtime_error("overlap worker request missing required field: " + key);
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

size_t findJsonValueFrom(const std::string& text, const std::string& key, size_t searchStart)
{
	std::string pattern = "\"" + key + "\"";
	size_t keyPos = text.find(pattern, searchStart);
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

size_t findJsonValue(const std::string& text, const std::string& key)
{
	return findJsonValueFrom(text, key, 0);
}

std::string jsonStringFrom(const std::string& text, const std::string& key, size_t searchStart)
{
	size_t value = findJsonValueFrom(text, key, searchStart);
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

std::string jsonString(const std::string& text, const std::string& key)
{
	return jsonStringFrom(text, key, 0);
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

double jsonDouble(const std::string& text, const std::string& key)
{
	size_t value = findJsonValue(text, key);
	char* end = nullptr;
	double parsed = std::strtod(text.c_str() + value, &end);
	if (end == text.c_str() + value)
	{
		throw std::runtime_error("manifest key is not number: " + key);
	}
	return parsed;
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
	if (schema != "cuflye-overlap-replay-fixture-v0")
	{
		throw std::runtime_error("unsupported fixture schema: " + schema);
	}

	FixtureManifest manifest;
	manifest.queryId = jsonInt(text, "query_id");
	manifest.queryLength = static_cast<int32_t>(jsonInt(text, "query_length"));
	manifest.expectedCandidateRecords = static_cast<uint64_t>(jsonInt(text, "candidate_records"));
	manifest.expectedTargetRecords = static_cast<uint64_t>(jsonInt(text, "target_records"));
	manifest.expectedOracleOverlapRecords =
		static_cast<uint64_t>(jsonInt(text, "oracle_overlap_records"));
	size_t filesObject = findJsonValue(text, "files");
	if (filesObject >= text.size() || text[filesObject] != '{')
	{
		throw std::runtime_error("manifest files key is not an object");
	}
	manifest.files.candidates = jsonStringFrom(text, "candidates", filesObject);
	manifest.files.filteredPositions = jsonStringFrom(text, "filtered_positions", filesObject);
	manifest.files.targets = jsonStringFrom(text, "targets", filesObject);
	manifest.files.oracleOverlaps = jsonStringFrom(text, "oracle_overlaps", filesObject);

	manifest.params.forceLocal = jsonBool(text, "force_local");
	manifest.params.maxOverlaps = static_cast<int32_t>(jsonInt(text, "max_overlaps"));
	manifest.params.kmerSize = static_cast<int32_t>(jsonInt(text, "kmer_size"));
	manifest.params.minKmerSurvivalRate =
		static_cast<float>(jsonDouble(text, "min_kmer_survival_rate"));
	manifest.params.largeGapPenalty =
		static_cast<float>(jsonDouble(text, "chain_large_gap_penalty"));
	manifest.params.smallGapPenalty =
		static_cast<float>(jsonDouble(text, "chain_small_gap_penalty"));
	manifest.params.gapJumpThreshold =
		static_cast<int32_t>(jsonInt(text, "chain_gap_jump_threshold"));
	manifest.params.maxGap = static_cast<int32_t>(jsonInt(text, "max_jump_gap"));
	manifest.params.maximumJump = static_cast<int32_t>(jsonInt(text, "maximum_jump"));
	manifest.params.minimumOverlap = static_cast<int32_t>(jsonInt(text, "minimum_overlap"));
	manifest.params.maximumOverhang = static_cast<int32_t>(jsonInt(text, "maximum_overhang"));
	manifest.params.checkOverhang = jsonBool(text, "check_overhang");
	manifest.params.keepAlignment = jsonBool(text, "keep_alignment");
	manifest.params.onlyMaxExt = jsonBool(text, "only_max_ext");
	manifest.params.nuclAlignment = jsonBool(text, "nucl_alignment");
	manifest.params.partitionBadMappings = jsonBool(text, "partition_bad_mappings");
	manifest.params.useHpc = jsonBool(text, "use_hpc");
	manifest.params.maxDivergence = static_cast<float>(jsonDouble(text, "max_divergence"));
	manifest.params.sampleRate = static_cast<float>(jsonDouble(text, "sample_rate"));
	return manifest;
}

void requireSupportedShape(const FixtureManifest& manifest)
{
	std::vector<std::string> unsupported;
	if (manifest.params.nuclAlignment)
	{
		unsupported.push_back("nucl_alignment=true requires base-alignment replay");
	}
	if (manifest.params.partitionBadMappings)
	{
		unsupported.push_back("partition_bad_mappings=true requires trim replay");
	}
	if (manifest.params.keepAlignment)
	{
		unsupported.push_back("keep_alignment=true is outside M4c prototype scope");
	}
	if (!manifest.params.onlyMaxExt)
	{
		unsupported.push_back("only_max_ext=false is outside M4c prototype scope");
	}
	if (manifest.params.maxOverlaps != 0)
	{
		unsupported.push_back("max_overlaps!=0 is outside M4c prototype scope");
	}
	if (!unsupported.empty())
	{
		std::ostringstream message;
		message << "unsupported overlap CUDA replay shape";
		for (const auto& item : unsupported) message << "; " << item;
		throw std::runtime_error(message.str());
	}
}

std::vector<std::string> splitTabs(const std::string& line)
{
	std::vector<std::string> fields;
	std::string field;
	std::stringstream stream(line);
	while (std::getline(stream, field, '\t')) fields.push_back(field);
	return fields;
}

std::vector<CandidateRecord> loadCandidates(const std::string& path, int64_t queryId)
{
	std::ifstream input(path);
	if (!input)
	{
		throw std::runtime_error("cannot read candidates TSV: " + path);
	}
	std::vector<CandidateRecord> records;
	std::string line;
	size_t lineNumber = 0;
	while (std::getline(input, line))
	{
		++lineNumber;
		auto fields = splitTabs(line);
		if (fields.size() != 6)
		{
			throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
									 ": expected 6 candidate fields");
		}
		CandidateRecord record{};
		record.queryId = std::stoll(fields[0]);
		record.queryPos = static_cast<int32_t>(std::stoll(fields[1]));
		record.kmer = static_cast<uint64_t>(std::stoull(fields[2]));
		record.targetId = std::stoll(fields[3]);
		record.targetPos = static_cast<int32_t>(std::stoll(fields[4]));
		record.targetStrand = fields[5] == "+" ? '+' : '-';
		if (record.queryId != queryId)
		{
			throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
									 ": candidate query_id does not match manifest");
		}
		records.push_back(record);
	}
	if (records.empty())
	{
		throw std::runtime_error("candidate fixture is empty: " + path);
	}
	return records;
}

std::vector<int32_t> loadFilteredPositions(const std::string& path)
{
	std::ifstream input(path);
	if (!input)
	{
		throw std::runtime_error("cannot read filtered positions TSV: " + path);
	}
	std::vector<int32_t> positions;
	std::string line;
	size_t lineNumber = 0;
	while (std::getline(input, line))
	{
		++lineNumber;
		if (line.empty()) continue;
		int64_t parsed = std::stoll(line);
		if (parsed < 0 || parsed > std::numeric_limits<int32_t>::max())
		{
			throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
									 ": filtered position outside int32 range");
		}
		positions.push_back(static_cast<int32_t>(parsed));
	}
	std::sort(positions.begin(), positions.end());
	return positions;
}

std::map<int64_t, int32_t> loadTargets(const std::string& path)
{
	std::ifstream input(path);
	if (!input)
	{
		throw std::runtime_error("cannot read targets TSV: " + path);
	}
	std::map<int64_t, int32_t> targets;
	std::string line;
	size_t lineNumber = 0;
	while (std::getline(input, line))
	{
		++lineNumber;
		auto fields = splitTabs(line);
		if (fields.size() != 2)
		{
			throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
									 ": expected target_id and length");
		}
		int64_t targetId = std::stoll(fields[0]);
		int64_t length = std::stoll(fields[1]);
		if (targetId == 0 || length <= 0 || length > std::numeric_limits<int32_t>::max())
		{
			throw std::runtime_error(path + ":" + std::to_string(lineNumber) +
									 ": invalid target id or length");
		}
		targets[targetId] = static_cast<int32_t>(length);
	}
	if (targets.empty())
	{
		throw std::runtime_error("target fixture is empty: " + path);
	}
	return targets;
}

std::vector<TargetGroup> buildGroups(std::vector<CandidateRecord>& candidates,
									 const std::map<int64_t, int32_t>& targets,
									 int32_t queryLength)
{
	std::vector<TargetGroup> groups;
	std::set<int64_t> seenTargets;
	size_t start = 0;
	while (start < candidates.size())
	{
		size_t end = start + 1;
		int64_t targetId = candidates[start].targetId;
		while (end < candidates.size() && candidates[end].targetId == targetId) ++end;
		if (!seenTargets.insert(targetId).second)
		{
			throw std::runtime_error("candidate records contain non-contiguous target group");
		}
		auto target = targets.find(targetId);
		if (target == targets.end())
		{
			throw std::runtime_error("missing target length for target_id " +
									 std::to_string(targetId));
		}

		TargetGroup group{};
		group.targetId = targetId;
		group.targetLen = target->second;
		group.start = static_cast<uint32_t>(start);
		group.count = static_cast<uint32_t>(end - start);
		group.minCur = candidates[start].queryPos;
		group.maxCur = candidates[start].queryPos;
		group.minExt = candidates[start].targetPos;
		group.maxExt = candidates[start].targetPos;
		bool querySorted = true;
		for (size_t index = start; index < end; ++index)
		{
			group.minCur = std::min(group.minCur, candidates[index].queryPos);
			group.maxCur = std::max(group.maxCur, candidates[index].queryPos);
			group.minExt = std::min(group.minExt, candidates[index].targetPos);
			group.maxExt = std::max(group.maxExt, candidates[index].targetPos);
			if (index > start && candidates[index].queryPos < candidates[index - 1].queryPos)
			{
				querySorted = false;
			}
		}
		if (!querySorted)
		{
			throw std::runtime_error("candidate target group is not sorted by query position");
		}
		group.extSorted = group.targetLen > queryLength ? 1 : 0;
		if (group.extSorted)
		{
			std::sort(candidates.begin() + start, candidates.begin() + end,
					  [](const CandidateRecord& lhs, const CandidateRecord& rhs)
					  {
						  return lhs.targetPos < rhs.targetPos;
					  });
		}
		groups.push_back(group);
		start = end;
	}
	return groups;
}

LoadedFixture loadFixture(const std::string& fixtureDir)
{
	LoadedFixture fixture;
	fixture.fixtureDir = fixtureDir;
	fixture.name = baseName(fixtureDir);
	fixture.manifest = loadManifest(fixtureDir);
	requireSupportedShape(fixture.manifest);

	fixture.candidates =
		loadCandidates(joinPath(fixtureDir, fixture.manifest.files.candidates),
					   fixture.manifest.queryId);
	fixture.filteredPositions =
		loadFilteredPositions(joinPath(fixtureDir, fixture.manifest.files.filteredPositions));
	std::map<int64_t, int32_t> targets =
		loadTargets(joinPath(fixtureDir, fixture.manifest.files.targets));
	if (fixture.candidates.size() != fixture.manifest.expectedCandidateRecords)
	{
		throw std::runtime_error("candidate record count does not match manifest");
	}
	if (targets.size() != fixture.manifest.expectedTargetRecords)
	{
		throw std::runtime_error("target record count does not match manifest");
	}
	fixture.groups = buildGroups(fixture.candidates, targets, fixture.manifest.queryLength);
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

__device__ int32_t overlapRange(int32_t begin, int32_t end)
{
	return end - begin;
}

__device__ int32_t overlapLrOverhang(const DeviceOverlap& overlap)
{
	int32_t left = min(overlap.curBegin, overlap.extBegin);
	int32_t right = min(overlap.curLen - overlap.curEnd, overlap.extLen - overlap.extEnd);
	return max(left, right);
}

__device__ bool overlapTest(const DeviceOverlap& overlap, const DeviceParams& params)
{
	int32_t curRange = overlapRange(overlap.curBegin, overlap.curEnd);
	int32_t extRange = overlapRange(overlap.extBegin, overlap.extEnd);
	if (curRange < params.minimumOverlap || extRange < params.minimumOverlap) return false;

	int32_t lengthDiff = abs(curRange - extRange);
	if (static_cast<float>(lengthDiff) > 0.5f * static_cast<float>(min(curRange, extRange)))
	{
		return false;
	}

	if (overlap.curId == overlap.extId)
	{
		int32_t intersect = min(overlap.curEnd, overlap.extEnd) -
							max(overlap.curBegin, overlap.extBegin);
		if (static_cast<float>(intersect) > static_cast<float>(curRange) / 2.0f)
		{
			return false;
		}
	}

	if (overlap.curId == -overlap.extId)
	{
		int32_t intersect = min(overlap.curEnd, overlap.extLen - overlap.extBegin) -
							max(overlap.curBegin, overlap.extLen - overlap.extEnd);
		if (static_cast<float>(intersect) > static_cast<float>(curRange) / 2.0f)
		{
			return false;
		}
	}

	if (!params.forceLocal && params.checkOverhang &&
		overlapLrOverhang(overlap) > params.maximumOverhang)
	{
		return false;
	}
	return true;
}

__global__ void overlapChainKernel(const CandidateRecord* candidates,
								   const TargetGroup* groups,
								   uint32_t groupCount,
								   const int32_t* filteredPositions,
								   uint32_t filteredCount,
								   DeviceParams params,
								   const DeviceParams* packedParams,
								   int32_t* scoreTable,
								   int32_t* backtrackTable,
								   uint8_t* orderedUsed,
								   DeviceOverlap* output)
{
	uint32_t groupId = blockIdx.x;
	if (groupId >= groupCount || threadIdx.x != 0) return;

	TargetGroup group = groups[groupId];
	DeviceParams queryParams = packedParams == nullptr ?
		params : packedParams[group.paramsIndex];
	const uint32_t start = group.start;
	const uint32_t count = group.count;
	DeviceOverlap best{};
	best.valid = 0;
	output[groupId] = best;

	if (count == 0) return;

	uint32_t uniqueMatches = 0;
	int32_t prevPos = 0;
	for (uint32_t local = 0; local < count; ++local)
	{
		int32_t curPos = candidates[start + local].queryPos;
		if (curPos != prevPos)
		{
			++uniqueMatches;
			prevPos = curPos;
		}
	}
	if (static_cast<float>(uniqueMatches) <
		queryParams.minKmerSurvivalRate * static_cast<float>(queryParams.minimumOverlap))
	{
		return;
	}

	if (group.maxCur - group.minCur < queryParams.minimumOverlap ||
		group.maxExt - group.minExt < queryParams.minimumOverlap)
	{
		return;
	}
	if (queryParams.checkOverhang && !queryParams.forceLocal)
	{
		if (min(group.minCur, group.minExt) > queryParams.maximumOverhang) return;
		if (min(queryParams.queryLen - group.maxCur, group.targetLen - group.maxExt) >
			queryParams.maximumOverhang)
		{
			return;
		}
	}

	for (uint32_t local = 0; local < count; ++local)
	{
		scoreTable[start + local] = 0;
		backtrackTable[start + local] = -1;
		orderedUsed[start + local] = 0;
	}

	for (uint32_t i = 1; i < count; ++i)
	{
		int32_t maxScore = 0;
		int32_t maxId = 0;
		int32_t curNext = candidates[start + i].queryPos;
		int32_t extNext = candidates[start + i].targetPos;

		for (int32_t j = static_cast<int32_t>(i) - 1; j >= 0; --j)
		{
			int32_t curPrev = candidates[start + j].queryPos;
			int32_t extPrev = candidates[start + j].targetPos;
			int32_t curDelta = curNext - curPrev;
			int32_t extDelta = extNext - extPrev;
			int32_t jumpDiv = abs(curDelta - extDelta);
			if (0 < curDelta && curDelta < queryParams.maximumJump &&
				0 < extDelta && extDelta < queryParams.maximumJump &&
				jumpDiv <= queryParams.maxGap)
			{
				int32_t matchScore = min(min(curDelta, extDelta), queryParams.kmerSize);
				float gapPenalty = jumpDiv > queryParams.gapJumpThreshold ?
					queryParams.largeGapPenalty : queryParams.smallGapPenalty;
				int32_t gapCost = static_cast<int32_t>(gapPenalty * static_cast<float>(jumpDiv));
				int32_t nextScore = scoreTable[start + j] + matchScore - gapCost;
				if (nextScore > maxScore)
				{
					maxScore = nextScore;
					maxId = j;
					if (jumpDiv == 0 && curDelta < queryParams.kmerSize) break;
				}
			}
			if (group.extSorted && extNext - extPrev > queryParams.maximumJump) break;
			if (!group.extSorted && curNext - curPrev > queryParams.maximumJump) break;
		}

		scoreTable[start + i] = max(maxScore, queryParams.kmerSize);
		if (maxScore > queryParams.kmerSize)
		{
			backtrackTable[start + i] = maxId;
		}
	}

	for (uint32_t ordered = 0; ordered < count; ++ordered)
	{
		int32_t chainStart = -1;
		int32_t bestScore = INT_MIN;
		for (uint32_t local = 0; local < count; ++local)
		{
			if (orderedUsed[start + local]) continue;
			int32_t score = scoreTable[start + local];
			if (chainStart == -1 || score > bestScore)
			{
				chainStart = static_cast<int32_t>(local);
				bestScore = score;
			}
		}
		if (chainStart == -1) break;
		orderedUsed[start + chainStart] = 1;
		if (backtrackTable[start + chainStart] == -1) continue;

		int32_t lastMatch = chainStart;
		int32_t firstMatch = 0;
		int32_t chainLength = 0;
		int32_t pos = chainStart;
		while (pos != -1)
		{
			firstMatch = pos;
			++chainLength;
			int32_t newPos = backtrackTable[start + pos];
			backtrackTable[start + pos] = -1;
			pos = newPos;
		}

		DeviceOverlap overlap{};
		overlap.curId = queryParams.queryId;
		overlap.curBegin = candidates[start + firstMatch].queryPos;
		overlap.curEnd = candidates[start + lastMatch].queryPos + queryParams.kmerSize - 1;
		overlap.curLen = queryParams.queryLen;
		overlap.extId = group.targetId;
		overlap.extBegin = candidates[start + firstMatch].targetPos;
		overlap.extEnd = candidates[start + lastMatch].targetPos + queryParams.kmerSize - 1;
		overlap.extLen = group.targetLen;
		overlap.score = scoreTable[start + lastMatch] - scoreTable[start + firstMatch] +
						queryParams.kmerSize - 1;
		overlap.chainLength = chainLength;
		overlap.valid = 0;

		if (!overlapTest(overlap, queryParams)) continue;
		if (!best.valid || overlap.score > best.score)
		{
			best = overlap;
			best.valid = 1;
		}
	}

	if (!best.valid) return;
	(void)filteredPositions;
	(void)filteredCount;
	output[groupId] = best;
}

__global__ void overlapChainReduceKernel(const CandidateRecord* candidates,
										 const TargetGroup* groups,
										 uint32_t groupCount,
										 const int32_t* filteredPositions,
										 uint32_t filteredCount,
										 DeviceParams params,
										 const DeviceParams* packedParams,
										 int32_t* scoreTable,
										 int32_t* backtrackTable,
										 uint8_t* orderedUsed,
										 DeviceOverlap* output)
{
	uint32_t groupId = blockIdx.x;
	uint32_t lane = threadIdx.x;
	if (groupId >= groupCount) return;

	__shared__ int32_t sharedScore[OVERLAP_CHAIN_REDUCE_THREADS];
	__shared__ int32_t sharedId[OVERLAP_CHAIN_REDUCE_THREADS];
	__shared__ int32_t skipGroup;
	__shared__ int32_t breakJ;

	TargetGroup group = groups[groupId];
	DeviceParams queryParams = packedParams == nullptr ?
		params : packedParams[group.paramsIndex];
	const uint32_t start = group.start;
	const uint32_t count = group.count;
	if (lane == 0)
	{
		DeviceOverlap empty{};
		empty.valid = 0;
		output[groupId] = empty;
		skipGroup = 0;
	}
	__syncthreads();
	if (count == 0) return;

	if (lane == 0)
	{
		uint32_t uniqueMatches = 0;
		int32_t prevPos = 0;
		for (uint32_t local = 0; local < count; ++local)
		{
			int32_t curPos = candidates[start + local].queryPos;
			if (curPos != prevPos)
			{
				++uniqueMatches;
				prevPos = curPos;
			}
		}
		if (static_cast<float>(uniqueMatches) <
			queryParams.minKmerSurvivalRate * static_cast<float>(queryParams.minimumOverlap))
		{
			skipGroup = 1;
		}
		if (group.maxCur - group.minCur < queryParams.minimumOverlap ||
			group.maxExt - group.minExt < queryParams.minimumOverlap)
		{
			skipGroup = 1;
		}
		if (queryParams.checkOverhang && !queryParams.forceLocal)
		{
			if (min(group.minCur, group.minExt) > queryParams.maximumOverhang) skipGroup = 1;
			if (min(queryParams.queryLen - group.maxCur, group.targetLen - group.maxExt) >
				queryParams.maximumOverhang)
			{
				skipGroup = 1;
			}
		}
	}
	__syncthreads();
	if (skipGroup) return;

	for (uint32_t local = lane; local < count; local += blockDim.x)
	{
		scoreTable[start + local] = 0;
		backtrackTable[start + local] = -1;
		orderedUsed[start + local] = 0;
	}
	__syncthreads();

	for (uint32_t i = 1; i < count; ++i)
	{
		int32_t curNext = candidates[start + i].queryPos;
		int32_t extNext = candidates[start + i].targetPos;

		// Preserve Flye's early-stop boundary before parallel predecessor scoring.
		if (lane == 0)
		{
			int32_t maxScore = 0;
			breakJ = -1;
			for (int32_t j = static_cast<int32_t>(i) - 1; j >= 0; --j)
			{
				int32_t curPrev = candidates[start + j].queryPos;
				int32_t extPrev = candidates[start + j].targetPos;
				int32_t curDelta = curNext - curPrev;
				int32_t extDelta = extNext - extPrev;
				int32_t jumpDiv = abs(curDelta - extDelta);
				if (0 < curDelta && curDelta < queryParams.maximumJump &&
					0 < extDelta && extDelta < queryParams.maximumJump &&
					jumpDiv <= queryParams.maxGap)
				{
					int32_t matchScore = min(min(curDelta, extDelta), queryParams.kmerSize);
					float gapPenalty = jumpDiv > queryParams.gapJumpThreshold ?
						queryParams.largeGapPenalty : queryParams.smallGapPenalty;
					int32_t gapCost =
						static_cast<int32_t>(gapPenalty * static_cast<float>(jumpDiv));
					int32_t nextScore = scoreTable[start + j] + matchScore - gapCost;
					if (nextScore > maxScore)
					{
						maxScore = nextScore;
						if (jumpDiv == 0 && curDelta < queryParams.kmerSize)
						{
							breakJ = j;
							break;
						}
					}
				}
				if (group.extSorted && extNext - extPrev > queryParams.maximumJump) break;
				if (!group.extSorted && curNext - curPrev > queryParams.maximumJump) break;
			}
		}
		__syncthreads();

		int32_t localScore = 0;
		int32_t localId = 0;
		for (int32_t j = static_cast<int32_t>(i) - 1 - static_cast<int32_t>(lane);
			 j >= 0; j -= static_cast<int32_t>(blockDim.x))
		{
			if (breakJ != -1 && j < breakJ) continue;
			int32_t curPrev = candidates[start + j].queryPos;
			int32_t extPrev = candidates[start + j].targetPos;
			int32_t curDelta = curNext - curPrev;
			int32_t extDelta = extNext - extPrev;
			int32_t jumpDiv = abs(curDelta - extDelta);
			if (0 < curDelta && curDelta < queryParams.maximumJump &&
				0 < extDelta && extDelta < queryParams.maximumJump &&
				jumpDiv <= queryParams.maxGap)
			{
				int32_t matchScore = min(min(curDelta, extDelta), queryParams.kmerSize);
				float gapPenalty = jumpDiv > queryParams.gapJumpThreshold ?
					queryParams.largeGapPenalty : queryParams.smallGapPenalty;
				int32_t gapCost = static_cast<int32_t>(gapPenalty * static_cast<float>(jumpDiv));
				int32_t nextScore = scoreTable[start + j] + matchScore - gapCost;
				if (nextScore > localScore || (nextScore == localScore && j > localId))
				{
					localScore = nextScore;
					localId = j;
				}
			}
		}

		sharedScore[lane] = localScore;
		sharedId[lane] = localId;
		__syncthreads();
		for (uint32_t offset = blockDim.x / 2; offset > 0; offset >>= 1)
		{
			if (lane < offset)
			{
				int32_t otherScore = sharedScore[lane + offset];
				int32_t otherId = sharedId[lane + offset];
				if (otherScore > sharedScore[lane] ||
					(otherScore == sharedScore[lane] && otherId > sharedId[lane]))
				{
					sharedScore[lane] = otherScore;
					sharedId[lane] = otherId;
				}
			}
			__syncthreads();
		}

		if (lane == 0)
		{
			scoreTable[start + i] = max(sharedScore[0], queryParams.kmerSize);
			if (sharedScore[0] > queryParams.kmerSize)
			{
				backtrackTable[start + i] = sharedId[0];
			}
		}
		__syncthreads();
	}

	if (lane == 0)
	{
		DeviceOverlap best{};
		best.valid = 0;
		for (uint32_t ordered = 0; ordered < count; ++ordered)
		{
			int32_t chainStart = -1;
			int32_t bestScore = INT_MIN;
			for (uint32_t local = 0; local < count; ++local)
			{
				if (orderedUsed[start + local]) continue;
				int32_t score = scoreTable[start + local];
				if (chainStart == -1 || score > bestScore)
				{
					chainStart = static_cast<int32_t>(local);
					bestScore = score;
				}
			}
			if (chainStart == -1) break;
			orderedUsed[start + chainStart] = 1;
			if (backtrackTable[start + chainStart] == -1) continue;

			int32_t lastMatch = chainStart;
			int32_t firstMatch = 0;
			int32_t chainLength = 0;
			int32_t pos = chainStart;
			while (pos != -1)
			{
				firstMatch = pos;
				++chainLength;
				int32_t newPos = backtrackTable[start + pos];
				backtrackTable[start + pos] = -1;
				pos = newPos;
			}

			DeviceOverlap overlap{};
			overlap.curId = queryParams.queryId;
			overlap.curBegin = candidates[start + firstMatch].queryPos;
			overlap.curEnd = candidates[start + lastMatch].queryPos + queryParams.kmerSize - 1;
			overlap.curLen = queryParams.queryLen;
			overlap.extId = group.targetId;
			overlap.extBegin = candidates[start + firstMatch].targetPos;
			overlap.extEnd = candidates[start + lastMatch].targetPos + queryParams.kmerSize - 1;
			overlap.extLen = group.targetLen;
			overlap.score = scoreTable[start + lastMatch] - scoreTable[start + firstMatch] +
							queryParams.kmerSize - 1;
			overlap.chainLength = chainLength;
			overlap.valid = 0;

			if (!overlapTest(overlap, queryParams)) continue;
			if (!best.valid || overlap.score > best.score)
			{
				best = overlap;
				best.valid = 1;
			}
		}
		if (best.valid) output[groupId] = best;
	}
	(void)filteredPositions;
	(void)filteredCount;
}

int32_t hostOverlapLrOverhang(const DeviceOverlap& overlap)
{
	int32_t left = std::min(overlap.curBegin, overlap.extBegin);
	int32_t right = std::min(overlap.curLen - overlap.curEnd,
							 overlap.extLen - overlap.extEnd);
	return std::max(left, right);
}

bool hostOverlapTest(const DeviceOverlap& overlap, const DeviceParams& params)
{
	int32_t curRange = overlap.curEnd - overlap.curBegin;
	int32_t extRange = overlap.extEnd - overlap.extBegin;
	if (curRange < params.minimumOverlap || extRange < params.minimumOverlap) return false;

	int32_t lengthDiff = std::abs(curRange - extRange);
	if (static_cast<float>(lengthDiff) >
		0.5f * static_cast<float>(std::min(curRange, extRange)))
	{
		return false;
	}

	if (overlap.curId == overlap.extId)
	{
		int32_t intersect = std::min(overlap.curEnd, overlap.extEnd) -
							std::max(overlap.curBegin, overlap.extBegin);
		if (static_cast<float>(intersect) > static_cast<float>(curRange) / 2.0f)
		{
			return false;
		}
	}

	if (overlap.curId == -overlap.extId)
	{
		int32_t intersect = std::min(overlap.curEnd, overlap.extLen - overlap.extBegin) -
							std::max(overlap.curBegin, overlap.extLen - overlap.extEnd);
		if (static_cast<float>(intersect) > static_cast<float>(curRange) / 2.0f)
		{
			return false;
		}
	}

	if (!params.forceLocal && params.checkOverhang &&
		hostOverlapLrOverhang(overlap) > params.maximumOverhang)
	{
		return false;
	}
	return true;
}

DeviceParams makeDeviceParams(const FixtureManifest& manifest)
{
	DeviceParams params{};
	params.queryId = manifest.queryId;
	params.queryLen = manifest.queryLength;
	params.kmerSize = manifest.params.kmerSize;
	params.minKmerSurvivalRate = manifest.params.minKmerSurvivalRate;
	params.largeGapPenalty = manifest.params.largeGapPenalty;
	params.smallGapPenalty = manifest.params.smallGapPenalty;
	params.gapJumpThreshold = manifest.params.gapJumpThreshold;
	params.maxGap = manifest.params.maxGap;
	params.maximumJump = manifest.params.maximumJump;
	params.minimumOverlap = manifest.params.minimumOverlap;
	params.maximumOverhang = manifest.params.maximumOverhang;
	params.checkOverhang = manifest.params.checkOverhang ? 1 : 0;
	params.forceLocal = manifest.params.forceLocal ? 1 : 0;
	return params;
}

DeviceOverlap computeCpuGroupOverlap(const std::vector<CandidateRecord>& candidates,
									 const TargetGroup& group,
									 const DeviceParams& params,
									 std::vector<int32_t>& scoreTable,
									 std::vector<int32_t>& backtrackTable,
									 std::vector<uint8_t>& orderedUsed)
{
	const uint32_t start = group.start;
	const uint32_t count = group.count;
	DeviceOverlap best{};
	best.valid = 0;
	if (count == 0) return best;

	uint32_t uniqueMatches = 0;
	int32_t prevPos = 0;
	for (uint32_t local = 0; local < count; ++local)
	{
		int32_t curPos = candidates[start + local].queryPos;
		if (curPos != prevPos)
		{
			++uniqueMatches;
			prevPos = curPos;
		}
	}
	if (static_cast<float>(uniqueMatches) <
		params.minKmerSurvivalRate * static_cast<float>(params.minimumOverlap))
	{
		return best;
	}

	if (group.maxCur - group.minCur < params.minimumOverlap ||
		group.maxExt - group.minExt < params.minimumOverlap)
	{
		return best;
	}
	if (params.checkOverhang && !params.forceLocal)
	{
		if (std::min(group.minCur, group.minExt) > params.maximumOverhang) return best;
		if (std::min(params.queryLen - group.maxCur, group.targetLen - group.maxExt) >
			params.maximumOverhang)
		{
			return best;
		}
	}

	for (uint32_t local = 0; local < count; ++local)
	{
		scoreTable[start + local] = 0;
		backtrackTable[start + local] = -1;
		orderedUsed[start + local] = 0;
	}

	for (uint32_t i = 1; i < count; ++i)
	{
		int32_t maxScore = 0;
		int32_t maxId = 0;
		int32_t curNext = candidates[start + i].queryPos;
		int32_t extNext = candidates[start + i].targetPos;

		for (int32_t j = static_cast<int32_t>(i) - 1; j >= 0; --j)
		{
			int32_t curPrev = candidates[start + j].queryPos;
			int32_t extPrev = candidates[start + j].targetPos;
			int32_t curDelta = curNext - curPrev;
			int32_t extDelta = extNext - extPrev;
			int32_t jumpDiv = std::abs(curDelta - extDelta);
			if (0 < curDelta && curDelta < params.maximumJump &&
				0 < extDelta && extDelta < params.maximumJump &&
				jumpDiv <= params.maxGap)
			{
				int32_t matchScore = std::min(std::min(curDelta, extDelta), params.kmerSize);
				float gapPenalty = jumpDiv > params.gapJumpThreshold ?
					params.largeGapPenalty : params.smallGapPenalty;
				int32_t gapCost = static_cast<int32_t>(gapPenalty * static_cast<float>(jumpDiv));
				int32_t nextScore = scoreTable[start + j] + matchScore - gapCost;
				if (nextScore > maxScore)
				{
					maxScore = nextScore;
					maxId = j;
					if (jumpDiv == 0 && curDelta < params.kmerSize) break;
				}
			}
			if (group.extSorted && extNext - extPrev > params.maximumJump) break;
			if (!group.extSorted && curNext - curPrev > params.maximumJump) break;
		}

		scoreTable[start + i] = std::max(maxScore, params.kmerSize);
		if (maxScore > params.kmerSize)
		{
			backtrackTable[start + i] = maxId;
		}
	}

	for (uint32_t ordered = 0; ordered < count; ++ordered)
	{
		int32_t chainStart = -1;
		int32_t bestScore = INT_MIN;
		for (uint32_t local = 0; local < count; ++local)
		{
			if (orderedUsed[start + local]) continue;
			int32_t score = scoreTable[start + local];
			if (chainStart == -1 || score > bestScore)
			{
				chainStart = static_cast<int32_t>(local);
				bestScore = score;
			}
		}
		if (chainStart == -1) break;
		orderedUsed[start + chainStart] = 1;
		if (backtrackTable[start + chainStart] == -1) continue;

		int32_t lastMatch = chainStart;
		int32_t firstMatch = 0;
		int32_t chainLength = 0;
		int32_t pos = chainStart;
		while (pos != -1)
		{
			firstMatch = pos;
			++chainLength;
			int32_t newPos = backtrackTable[start + pos];
			backtrackTable[start + pos] = -1;
			pos = newPos;
		}

		DeviceOverlap overlap{};
		overlap.curId = params.queryId;
		overlap.curBegin = candidates[start + firstMatch].queryPos;
		overlap.curEnd = candidates[start + lastMatch].queryPos + params.kmerSize - 1;
		overlap.curLen = params.queryLen;
		overlap.extId = group.targetId;
		overlap.extBegin = candidates[start + firstMatch].targetPos;
		overlap.extEnd = candidates[start + lastMatch].targetPos + params.kmerSize - 1;
		overlap.extLen = group.targetLen;
		overlap.score = scoreTable[start + lastMatch] - scoreTable[start + firstMatch] +
						params.kmerSize - 1;
		overlap.chainLength = chainLength;
		overlap.valid = 0;

		if (!hostOverlapTest(overlap, params)) continue;
		if (!best.valid || overlap.score > best.score)
		{
			best = overlap;
			best.valid = 1;
		}
	}

	return best;
}

int32_t countFiltered(const std::vector<int32_t>& filteredPositions, const HostOverlap& overlap)
{
	int32_t count = 0;
	for (int32_t position : filteredPositions)
	{
		if (position < overlap.curBegin) continue;
		if (position > overlap.curEnd) break;
		++count;
	}
	return count;
}

float computeDivergence(const DeviceOverlap& deviceOverlap,
						const ReplayParameters& params,
						const std::vector<int32_t>& filteredPositions)
{
	HostOverlap overlap{};
	overlap.curBegin = deviceOverlap.curBegin;
	overlap.curEnd = deviceOverlap.curEnd;
	overlap.extBegin = deviceOverlap.extBegin;
	overlap.extEnd = deviceOverlap.extEnd;
	int32_t curRange = overlap.curEnd - overlap.curBegin;
	int32_t extRange = overlap.extEnd - overlap.extBegin;
	int32_t filteredCount = countFiltered(filteredPositions, overlap);
	float normLen = static_cast<float>(std::max(curRange, extRange) - filteredCount);
	float matchRate = static_cast<float>(deviceOverlap.chainLength) * params.sampleRate / normLen;
	matchRate = std::min(matchRate, 1.0f);
	return std::log(1.0f / matchRate) / static_cast<float>(params.kmerSize);
}

std::vector<HostOverlap> finalizeOverlaps(const std::vector<DeviceOverlap>& deviceOverlaps,
										  const ReplayParameters& params,
										  const std::vector<int32_t>& filteredPositions)
{
	std::vector<HostOverlap> overlaps;
	for (const auto& deviceOverlap : deviceOverlaps)
	{
		if (!deviceOverlap.valid) continue;
		float divergence = computeDivergence(deviceOverlap, params, filteredPositions);
		if (!(divergence < params.maxDivergence)) continue;
		overlaps.push_back({
			deviceOverlap.curId,
			deviceOverlap.curBegin,
			deviceOverlap.curEnd,
			deviceOverlap.curLen,
			deviceOverlap.extId,
			deviceOverlap.extBegin,
			deviceOverlap.extEnd,
			deviceOverlap.extLen,
			deviceOverlap.score,
			divergence
		});
	}
	return overlaps;
}

void writeOverlaps(const std::string& path, const std::vector<HostOverlap>& overlaps)
{
	std::ofstream output(path);
	if (!output)
	{
		throw std::runtime_error("cannot write output TSV: " + path);
	}
	output << std::setprecision(9);
	for (const auto& overlap : overlaps)
	{
		output << overlap.curId << "\t"
			   << overlap.curBegin << "\t"
			   << overlap.curEnd << "\t"
			   << overlap.curLen << "\t"
			   << overlap.extId << "\t"
			   << overlap.extBegin << "\t"
			   << overlap.extEnd << "\t"
			   << overlap.extLen << "\t"
			   << overlap.score << "\t"
			   << overlap.seqDivergence << "\n";
	}
}

Options parseArgs(int argc, char** argv)
{
	Options options;
	for (int index = 1; index < argc; ++index)
	{
		std::string arg = argv[index];
		auto requireValue = [&](const std::string& name) -> std::string
		{
			if (index + 1 >= argc)
			{
				throw std::runtime_error("missing value for " + name);
			}
			return argv[++index];
		};

		if (arg == "--fixture-dir") options.fixtureDir = requireValue(arg);
		else if (arg == "--output-tsv") options.outputTsv = requireValue(arg);
		else if (arg == "--json-output") options.jsonOutput = requireValue(arg);
		else if (arg == "--batch-fixtures-file") options.batchFixturesFile = requireValue(arg);
		else if (arg == "--batch-output-dir") options.batchOutputDir = requireValue(arg);
		else if (arg == "--batch-json-output") options.batchJsonOutput = requireValue(arg);
		else if (arg == "--worker-request-json") options.workerRequestJson = requireValue(arg);
		else if (arg == "--worker-requests-jsonl") options.workerRequestsJsonl = requireValue(arg);
		else if (arg == "--backend") options.backend = requireValue(arg);
		else if (arg == "--cuda-kernel-mode") options.cudaKernelMode = requireValue(arg);
		else if (arg == "--batch-execution") options.batchExecution = requireValue(arg);
		else if (arg == "--device") options.device = std::stoi(requireValue(arg));
		else if (arg == "--warmup-runs")
		{
			options.warmupRuns = static_cast<uint32_t>(std::stoul(requireValue(arg)));
		}
		else if (arg == "--benchmark-runs")
		{
			options.benchmarkRuns = static_cast<uint32_t>(std::stoul(requireValue(arg)));
		}
		else if (arg == "--memory-budget-bytes")
		{
			options.hasMemoryBudget = true;
			options.memoryBudgetBytes = std::stoull(requireValue(arg));
		}
		else if (arg == "-h" || arg == "--help")
		{
			std::cout << "Usage: cuflye-cuda-overlap-chain-replay "
					  << "--fixture-dir DIR --output-tsv PATH --json-output PATH "
					  << "or --batch-fixtures-file PATH --batch-output-dir DIR "
					  << "--batch-json-output PATH "
					  << "or --worker-request-json PATH "
					  << "or --worker-requests-jsonl PATH "
					  << "[--backend cpu|cuda] [--device ID] "
					  << "[--cuda-kernel-mode serial|parallel-reduce] "
					  << "[--batch-execution per-fixture|packed] "
					  << "[--warmup-runs N] [--benchmark-runs N] "
					  << "[--memory-budget-bytes N]\n";
			std::exit(0);
		}
		else
		{
			throw std::runtime_error("unknown option: " + arg);
		}
	}
	bool batchMode = !options.batchFixturesFile.empty() ||
					 !options.batchOutputDir.empty() ||
					 !options.batchJsonOutput.empty();
	bool workerMode = !options.workerRequestJson.empty() || !options.workerRequestsJsonl.empty();
	if (workerMode)
	{
		if (!options.workerRequestJson.empty() && !options.workerRequestsJsonl.empty())
		{
			throw std::runtime_error("set only one worker request input");
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
	}
	else
	{
		if (options.fixtureDir.empty()) throw std::runtime_error("--fixture-dir is required");
		if (options.outputTsv.empty()) throw std::runtime_error("--output-tsv is required");
		if (options.jsonOutput.empty()) throw std::runtime_error("--json-output is required");
	}
	if (options.backend != "cuda" && options.backend != "cpu")
	{
		throw std::runtime_error("--backend must be cpu or cuda");
	}
	if (options.cudaKernelMode != "serial" && options.cudaKernelMode != "parallel-reduce")
	{
		throw std::runtime_error("--cuda-kernel-mode must be serial or parallel-reduce");
	}
	if (options.batchExecution != "per-fixture" && options.batchExecution != "packed")
	{
		throw std::runtime_error("--batch-execution must be per-fixture or packed");
	}
	if (!batchMode && options.batchExecution != "per-fixture")
	{
		throw std::runtime_error("--batch-execution=packed is only supported in batch mode");
	}
	if (options.batchExecution == "packed" && options.backend != "cuda")
	{
		throw std::runtime_error("--batch-execution=packed requires --backend cuda");
	}
	if (options.backend == "cpu" && options.cudaKernelMode != "serial")
	{
		throw std::runtime_error("--cuda-kernel-mode is only supported for cuda backend");
	}
	if (options.benchmarkRuns == 0)
	{
		throw std::runtime_error("--benchmark-runs must be greater than zero");
	}
	if (options.hasMemoryBudget && options.backend == "cpu")
	{
		throw std::runtime_error("--memory-budget-bytes is only supported for cuda backend");
	}
	return options;
}

size_t checkedBytes(size_t count, size_t size, const std::string& label)
{
	if (count > std::numeric_limits<size_t>::max() / size)
	{
		throw std::runtime_error("byte size overflow for " + label);
	}
	return count * size;
}

void initializeArena(const Options& options, CudaOverlapArena& arena)
{
	if (arena.initialized) return;
	arena.device = options.device;
	cuflye::cuda_raii::checkCuda(cudaSetDevice(options.device), "set CUDA device");
	cudaDeviceProp prop{};
	cuflye::cuda_raii::checkCuda(cudaGetDeviceProperties(&prop, options.device),
								 "get CUDA device properties");
	arena.deviceName = prop.name;
	cuflye::cuda_raii::checkCuda(cudaMemGetInfo(&arena.freeBytes, &arena.totalBytes),
								 "query CUDA memory");
	arena.initialized = true;
}

template <class T>
void ensureArenaBuffer(cuflye::cuda_raii::DeviceBuffer<T>& buffer,
					   size_t bytes,
					   const std::string& label,
					   CudaOverlapArena& arena)
{
	if (buffer.ensureCapacity(bytes, label))
	{
		++arena.allocations;
	}
	else
	{
		++arena.reuses;
	}
}

CudaRunSummary runCpu(const FixtureManifest& manifest,
					  const std::vector<CandidateRecord>& candidates,
					  const std::vector<int32_t>& filteredPositions,
					  const std::vector<TargetGroup>& groups,
					  std::vector<HostOverlap>& overlaps)
{
	CudaRunSummary summary;
	summary.backend = "cpu";
	summary.candidateRecords = candidates.size();
	summary.targetGroups = groups.size();
	summary.filteredPositions = filteredPositions.size();
	summary.requiredBytes = checkedBytes(candidates.size(), sizeof(int32_t), "CPU score table") * 2 +
							checkedBytes(candidates.size(), sizeof(uint8_t), "CPU ordered flags") +
							checkedBytes(groups.size(), sizeof(DeviceOverlap), "CPU output overlaps");

	DeviceParams params = makeDeviceParams(manifest);
	std::vector<int32_t> scoreTable(candidates.size());
	std::vector<int32_t> backtrackTable(candidates.size());
	std::vector<uint8_t> orderedUsed(candidates.size());
	std::vector<DeviceOverlap> deviceOverlaps(groups.size());

	auto chainStart = Clock::now();
	for (size_t groupIndex = 0; groupIndex < groups.size(); ++groupIndex)
	{
		deviceOverlaps[groupIndex] = computeCpuGroupOverlap(candidates, groups[groupIndex],
															 params, scoreTable,
															 backtrackTable, orderedUsed);
	}
	auto chainEnd = Clock::now();
	summary.cpuChainMs = elapsedMs(chainStart, chainEnd);

	auto finalizeStart = Clock::now();
	overlaps = finalizeOverlaps(deviceOverlaps, manifest.params, filteredPositions);
	auto finalizeEnd = Clock::now();
	summary.finalizeMs = elapsedMs(finalizeStart, finalizeEnd);
	summary.outputRecords = overlaps.size();
	summary.totalBeforeJsonMs = summary.cpuChainMs + summary.finalizeMs;
	return summary;
}

CudaRunSummary runCudaWithArena(const Options& options,
								const FixtureManifest& manifest,
								std::vector<CandidateRecord>& candidates,
								const std::vector<int32_t>& filteredPositions,
								const std::vector<TargetGroup>& groups,
								CudaOverlapArena& arena,
								std::vector<HostOverlap>& overlaps)
{
	initializeArena(options, arena);
	CudaRunSummary summary;
	summary.backend = "cuda";
	summary.cudaKernelMode = options.cudaKernelMode;
	summary.device = options.device;
	summary.deviceName = arena.deviceName;
	summary.freeBytes = arena.freeBytes;
	summary.totalBytes = arena.totalBytes;
	summary.candidateRecords = candidates.size();
	summary.targetGroups = groups.size();
	summary.filteredPositions = filteredPositions.size();

	size_t candidateBytes = checkedBytes(candidates.size(), sizeof(CandidateRecord), "candidates");
	size_t groupBytes = checkedBytes(groups.size(), sizeof(TargetGroup), "groups");
	size_t filteredBytes =
		checkedBytes(std::max<size_t>(filteredPositions.size(), 1), sizeof(int32_t),
					 "filtered positions");
	size_t tableBytes = checkedBytes(candidates.size(), sizeof(int32_t), "DP table");
	size_t usedBytes = checkedBytes(candidates.size(), sizeof(uint8_t), "ordered flags");
	size_t outputBytes = checkedBytes(groups.size(), sizeof(DeviceOverlap), "output overlaps");
	summary.requiredBytes = candidateBytes + groupBytes + filteredBytes +
							tableBytes * 2 + usedBytes + outputBytes;
	if (options.hasMemoryBudget && summary.requiredBytes > options.memoryBudgetBytes)
	{
		throw std::runtime_error("CUDA overlap replay memory budget exceeded: required=" +
								 std::to_string(summary.requiredBytes) +
								 " budget=" + std::to_string(options.memoryBudgetBytes));
	}

	size_t allocationsBefore = arena.allocations;
	size_t reusesBefore = arena.reuses;
	auto allocStart = Clock::now();
	ensureArenaBuffer(arena.candidates, candidateBytes, "batch candidates", arena);
	ensureArenaBuffer(arena.groups, groupBytes, "batch target groups", arena);
	ensureArenaBuffer(arena.filtered, filteredBytes, "batch filtered positions", arena);
	ensureArenaBuffer(arena.scores, tableBytes, "batch score table", arena);
	ensureArenaBuffer(arena.backtrack, tableBytes, "batch backtrack table", arena);
	ensureArenaBuffer(arena.used, usedBytes, "batch ordered flags", arena);
	ensureArenaBuffer(arena.output, outputBytes, "batch output overlaps", arena);
	auto allocEnd = Clock::now();
	summary.deviceAllocationMs = elapsedMs(allocStart, allocEnd);
	summary.arenaAllocations = arena.allocations - allocationsBefore;
	summary.arenaReuses = arena.reuses - reusesBefore;
	summary.arenaCapacityBytes = arena.capacityBytes();

	auto h2dStart = Clock::now();
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(arena.candidates.get(), candidates.data(), candidateBytes,
				   cudaMemcpyHostToDevice),
		"copy batch candidates to device");
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(arena.groups.get(), groups.data(), groupBytes, cudaMemcpyHostToDevice),
		"copy batch target groups to device");
	if (!filteredPositions.empty())
	{
		cuflye::cuda_raii::checkCuda(
			cudaMemcpy(arena.filtered.get(), filteredPositions.data(), filteredBytes,
					   cudaMemcpyHostToDevice),
			"copy batch filtered positions to device");
	}
	auto h2dEnd = Clock::now();
	summary.hostToDeviceMs = elapsedMs(h2dStart, h2dEnd);

	DeviceParams params = makeDeviceParams(manifest);
	auto kernelStart = Clock::now();
	if (options.cudaKernelMode == "serial")
	{
		overlapChainKernel<<<static_cast<unsigned int>(groups.size()), 1>>>(
			arena.candidates.get(),
			arena.groups.get(),
			static_cast<uint32_t>(groups.size()),
			arena.filtered.get(),
			static_cast<uint32_t>(filteredPositions.size()),
			params,
			nullptr,
			arena.scores.get(),
			arena.backtrack.get(),
			arena.used.get(),
			arena.output.get());
	}
	else
	{
		overlapChainReduceKernel<<<static_cast<unsigned int>(groups.size()),
								   OVERLAP_CHAIN_REDUCE_THREADS>>>(
			arena.candidates.get(),
			arena.groups.get(),
			static_cast<uint32_t>(groups.size()),
			arena.filtered.get(),
			static_cast<uint32_t>(filteredPositions.size()),
			params,
			nullptr,
			arena.scores.get(),
			arena.backtrack.get(),
			arena.used.get(),
			arena.output.get());
	}
	cuflye::cuda_raii::checkCuda(cudaGetLastError(), "launch batch overlap chain kernel");
	cuflye::cuda_raii::checkCuda(cudaDeviceSynchronize(), "synchronize batch overlap chain kernel");
	auto kernelEnd = Clock::now();
	summary.kernelMs = elapsedMs(kernelStart, kernelEnd);
	summary.kernelLaunches = 1;

	std::vector<DeviceOverlap> deviceOverlaps(groups.size());
	auto d2hStart = Clock::now();
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(deviceOverlaps.data(), arena.output.get(), outputBytes, cudaMemcpyDeviceToHost),
		"copy batch overlaps to host");
	auto d2hEnd = Clock::now();
	summary.deviceToHostMs = elapsedMs(d2hStart, d2hEnd);

	auto finalizeStart = Clock::now();
	overlaps = finalizeOverlaps(deviceOverlaps, manifest.params, filteredPositions);
	auto finalizeEnd = Clock::now();
	summary.finalizeMs = elapsedMs(finalizeStart, finalizeEnd);
	summary.outputRecords = overlaps.size();
	summary.totalBeforeJsonMs = summary.deviceAllocationMs +
								summary.hostToDeviceMs + summary.kernelMs +
								summary.deviceToHostMs + summary.finalizeMs;
	return summary;
}

CudaRunSummary runCuda(const Options& options,
					   const FixtureManifest& manifest,
					   std::vector<CandidateRecord>& candidates,
					   const std::vector<int32_t>& filteredPositions,
					   const std::vector<TargetGroup>& groups,
					   std::vector<HostOverlap>& overlaps)
{
	CudaRunSummary summary;
	summary.backend = "cuda";
	summary.cudaKernelMode = options.cudaKernelMode;
	summary.device = options.device;
	summary.candidateRecords = candidates.size();
	summary.targetGroups = groups.size();
	summary.filteredPositions = filteredPositions.size();

	auto setupStart = Clock::now();
	cuflye::cuda_raii::checkCuda(cudaSetDevice(options.device), "set CUDA device");
	cudaDeviceProp prop{};
	cuflye::cuda_raii::checkCuda(cudaGetDeviceProperties(&prop, options.device),
								 "get CUDA device properties");
	summary.deviceName = prop.name;
	cuflye::cuda_raii::checkCuda(cudaMemGetInfo(&summary.freeBytes, &summary.totalBytes),
								 "query CUDA memory");
	auto setupEnd = Clock::now();
	summary.setupMs = elapsedMs(setupStart, setupEnd);

	size_t candidateBytes = checkedBytes(candidates.size(), sizeof(CandidateRecord), "candidates");
	size_t groupBytes = checkedBytes(groups.size(), sizeof(TargetGroup), "groups");
	size_t filteredBytes =
		checkedBytes(std::max<size_t>(filteredPositions.size(), 1), sizeof(int32_t),
					 "filtered positions");
	size_t tableBytes = checkedBytes(candidates.size(), sizeof(int32_t), "DP table");
	size_t usedBytes = checkedBytes(candidates.size(), sizeof(uint8_t), "ordered flags");
	size_t outputBytes = checkedBytes(groups.size(), sizeof(DeviceOverlap), "output overlaps");
	summary.requiredBytes = candidateBytes + groupBytes + filteredBytes +
							tableBytes * 2 + usedBytes + outputBytes;
	if (options.hasMemoryBudget && summary.requiredBytes > options.memoryBudgetBytes)
	{
		throw std::runtime_error("CUDA overlap replay memory budget exceeded: required=" +
								 std::to_string(summary.requiredBytes) +
								 " budget=" + std::to_string(options.memoryBudgetBytes));
	}

	auto allocStart = Clock::now();
	cuflye::cuda_raii::DeviceBuffer<CandidateRecord> dCandidates(candidateBytes, "candidates");
	cuflye::cuda_raii::DeviceBuffer<TargetGroup> dGroups(groupBytes, "target groups");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dFiltered(filteredBytes, "filtered positions");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dScores(tableBytes, "score table");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dBacktrack(tableBytes, "backtrack table");
	cuflye::cuda_raii::DeviceBuffer<uint8_t> dUsed(usedBytes, "ordered flags");
	cuflye::cuda_raii::DeviceBuffer<DeviceOverlap> dOutput(outputBytes, "output overlaps");
	auto allocEnd = Clock::now();
	summary.deviceAllocationMs = elapsedMs(allocStart, allocEnd);

	auto h2dStart = Clock::now();
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(dCandidates.get(), candidates.data(), candidateBytes, cudaMemcpyHostToDevice),
		"copy candidates to device");
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(dGroups.get(), groups.data(), groupBytes, cudaMemcpyHostToDevice),
		"copy target groups to device");
	if (!filteredPositions.empty())
	{
		cuflye::cuda_raii::checkCuda(
			cudaMemcpy(dFiltered.get(), filteredPositions.data(), filteredBytes,
					   cudaMemcpyHostToDevice),
			"copy filtered positions to device");
	}
	auto h2dEnd = Clock::now();
	summary.hostToDeviceMs = elapsedMs(h2dStart, h2dEnd);

	DeviceParams params = makeDeviceParams(manifest);

	auto kernelStart = Clock::now();
	if (options.cudaKernelMode == "serial")
	{
		overlapChainKernel<<<static_cast<unsigned int>(groups.size()), 1>>>(
			dCandidates.get(),
			dGroups.get(),
			static_cast<uint32_t>(groups.size()),
			dFiltered.get(),
			static_cast<uint32_t>(filteredPositions.size()),
			params,
			nullptr,
			dScores.get(),
			dBacktrack.get(),
			dUsed.get(),
			dOutput.get());
	}
	else
	{
		overlapChainReduceKernel<<<static_cast<unsigned int>(groups.size()),
								   OVERLAP_CHAIN_REDUCE_THREADS>>>(
			dCandidates.get(),
			dGroups.get(),
			static_cast<uint32_t>(groups.size()),
			dFiltered.get(),
			static_cast<uint32_t>(filteredPositions.size()),
			params,
			nullptr,
			dScores.get(),
			dBacktrack.get(),
			dUsed.get(),
			dOutput.get());
	}
	cuflye::cuda_raii::checkCuda(cudaGetLastError(), "launch overlap chain kernel");
	cuflye::cuda_raii::checkCuda(cudaDeviceSynchronize(), "synchronize overlap chain kernel");
	auto kernelEnd = Clock::now();
	summary.kernelMs = elapsedMs(kernelStart, kernelEnd);
	summary.kernelLaunches = 1;

	std::vector<DeviceOverlap> deviceOverlaps(groups.size());
	auto d2hStart = Clock::now();
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(deviceOverlaps.data(), dOutput.get(), outputBytes, cudaMemcpyDeviceToHost),
		"copy overlaps to host");
	auto d2hEnd = Clock::now();
	summary.deviceToHostMs = elapsedMs(d2hStart, d2hEnd);

	auto finalizeStart = Clock::now();
	overlaps = finalizeOverlaps(deviceOverlaps, manifest.params, filteredPositions);
	auto finalizeEnd = Clock::now();
	summary.finalizeMs = elapsedMs(finalizeStart, finalizeEnd);
	summary.outputRecords = overlaps.size();
	summary.totalBeforeJsonMs = summary.parseMs + summary.setupMs +
								summary.deviceAllocationMs +
								summary.hostToDeviceMs + summary.kernelMs +
								summary.deviceToHostMs + summary.finalizeMs;
	return summary;
}

void attachBenchmarkStats(CudaRunSummary& summary,
						  const std::vector<CudaRunSummary>& timedRuns,
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
	for (const auto& run : timedRuns)
	{
		total += run.totalBeforeJsonMs;
		core += run.backend == "cuda" ? run.kernelMs : run.cpuChainMs;
		summary.benchmarkMinTotalMs =
			std::min(summary.benchmarkMinTotalMs, run.totalBeforeJsonMs);
		summary.benchmarkMaxTotalMs =
			std::max(summary.benchmarkMaxTotalMs, run.totalBeforeJsonMs);
	}
	summary.benchmarkMeanTotalMs = total / static_cast<double>(timedRuns.size());
	summary.benchmarkMeanCoreMs = core / static_cast<double>(timedRuns.size());
}

CudaRunSummary runCpuBenchmark(const Options& options,
							   const FixtureManifest& manifest,
							   const std::vector<CandidateRecord>& candidates,
							   const std::vector<int32_t>& filteredPositions,
							   const std::vector<TargetGroup>& groups,
							   std::vector<HostOverlap>& overlaps)
{
	std::vector<HostOverlap> scratch;
	for (uint32_t index = 0; index < options.warmupRuns; ++index)
	{
		(void)runCpu(manifest, candidates, filteredPositions, groups, scratch);
	}

	std::vector<CudaRunSummary> timedRuns;
	for (uint32_t index = 0; index < options.benchmarkRuns; ++index)
	{
		CudaRunSummary summary = runCpu(manifest, candidates, filteredPositions,
										groups, overlaps);
		timedRuns.push_back(summary);
	}
	CudaRunSummary summary = timedRuns.back();
	attachBenchmarkStats(summary, timedRuns, options.warmupRuns);
	return summary;
}

CudaRunSummary runCudaBenchmark(const Options& options,
								const FixtureManifest& manifest,
								std::vector<CandidateRecord>& candidates,
								const std::vector<int32_t>& filteredPositions,
								const std::vector<TargetGroup>& groups,
								std::vector<HostOverlap>& overlaps)
{
	std::vector<HostOverlap> scratch;
	for (uint32_t index = 0; index < options.warmupRuns; ++index)
	{
		(void)runCuda(options, manifest, candidates, filteredPositions, groups, scratch);
	}

	std::vector<CudaRunSummary> timedRuns;
	for (uint32_t index = 0; index < options.benchmarkRuns; ++index)
	{
		CudaRunSummary summary = runCuda(options, manifest, candidates,
										 filteredPositions, groups, overlaps);
		timedRuns.push_back(summary);
	}
	CudaRunSummary summary = timedRuns.back();
	attachBenchmarkStats(summary, timedRuns, options.warmupRuns);
	return summary;
}

void writeJsonSummary(const std::string& path,
					  const Options& options,
					  const FixtureManifest& manifest,
					  const CudaRunSummary& summary)
{
	std::ofstream output(path);
	if (!output)
	{
		throw std::runtime_error("cannot write JSON summary: " + path);
	}
	output << std::fixed << std::setprecision(6);
	output << "{\n"
		   << "  \"schema\": \"cuflye-cuda-overlap-chain-replay-v0\",\n"
		   << "  \"status\": \"ok\",\n"
		   << "  \"backend\": \"" << summary.backend << "\",\n"
		   << "  \"cuda_kernel_mode\": \"" << summary.cudaKernelMode << "\",\n"
		   << "  \"fixture_dir\": \"" << options.fixtureDir << "\",\n"
		   << "  \"output_tsv\": \"" << options.outputTsv << "\",\n"
		   << "  \"query_id\": " << manifest.queryId << ",\n"
		   << "  \"candidate_records\": " << summary.candidateRecords << ",\n"
		   << "  \"target_groups\": " << summary.targetGroups << ",\n"
		   << "  \"filtered_positions\": " << summary.filteredPositions << ",\n"
		   << "  \"output_records\": " << summary.outputRecords << ",\n";
	if (summary.backend == "cuda")
	{
		output << "  \"device\": {\n"
			   << "    \"id\": " << summary.device << ",\n"
			   << "    \"name\": \"" << summary.deviceName << "\",\n"
			   << "    \"free_bytes\": " << summary.freeBytes << ",\n"
			   << "    \"total_bytes\": " << summary.totalBytes << "\n"
			   << "  },\n";
	}
	else
	{
		output << "  \"device\": null,\n";
	}
	output
		   << "  \"memory\": {\n"
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
		   << "  \"arena\": {\n"
		   << "    \"allocations\": " << summary.arenaAllocations << ",\n"
		   << "    \"reuses\": " << summary.arenaReuses << ",\n"
		   << "    \"capacity_bytes\": " << summary.arenaCapacityBytes << "\n"
		   << "  },\n"
		   << "  \"supported_shape\": {\n"
		   << "    \"nucl_alignment\": false,\n"
		   << "    \"partition_bad_mappings\": false,\n"
		   << "    \"keep_alignment\": false,\n"
		   << "    \"only_max_ext\": true\n"
		   << "  }\n"
		   << "}\n";
}

double coreMs(const CudaRunSummary& summary)
{
	return summary.backend == "cuda" ? summary.kernelMs : summary.cpuChainMs;
}

struct BatchFixtureOutput
{
	std::string fixtureDir;
	std::string name;
	std::string outputTsv;
	int64_t queryId = 0;
	size_t candidateOffset = 0;
	size_t groupOffset = 0;
	size_t paramsIndex = 0;
	size_t candidateRecords = 0;
	size_t targetGroups = 0;
	size_t outputRecords = 0;
	CudaRunSummary summary;
};

PackedBatchLayout buildPackedBatchLayout(const std::vector<LoadedFixture>& fixtures)
{
	PackedBatchLayout layout;
	if (fixtures.empty())
	{
		throw std::runtime_error("cannot build packed layout for empty fixture set");
	}
	if (fixtures.size() > static_cast<size_t>(std::numeric_limits<int32_t>::max()))
	{
		throw std::runtime_error("too many fixtures for int32 params index");
	}

	for (size_t fixtureIndex = 0; fixtureIndex < fixtures.size(); ++fixtureIndex)
	{
		const auto& fixture = fixtures[fixtureIndex];
		size_t candidateOffset = layout.candidates.size();
		size_t groupOffset = layout.groups.size();
		if (candidateOffset > std::numeric_limits<uint32_t>::max())
		{
			throw std::runtime_error("packed candidate offset exceeds uint32 target group range");
		}
		layout.candidateOffsets.push_back(candidateOffset);
		layout.groupOffsets.push_back(groupOffset);
		layout.params.push_back(makeDeviceParams(fixture.manifest));
		layout.totalFilteredPositions += fixture.filteredPositions.size();
		layout.candidates.insert(layout.candidates.end(),
								 fixture.candidates.begin(),
								 fixture.candidates.end());
		for (const auto& group : fixture.groups)
		{
			TargetGroup packed = group;
			size_t packedStart = candidateOffset + static_cast<size_t>(group.start);
			if (packedStart > std::numeric_limits<uint32_t>::max())
			{
				throw std::runtime_error("packed group start exceeds uint32 range");
			}
			packed.start = static_cast<uint32_t>(packedStart);
			packed.paramsIndex = static_cast<int32_t>(fixtureIndex);
			layout.groups.push_back(packed);
		}
	}
	return layout;
}

CudaRunSummary runPackedCudaBatchOnce(const Options& options,
									  const std::vector<LoadedFixture>& fixtures,
									  const PackedBatchLayout& layout,
									  CudaOverlapArena& arena,
									  std::vector<std::vector<HostOverlap>>& outputs)
{
	initializeArena(options, arena);
	CudaRunSummary summary;
	summary.backend = "cuda";
	summary.cudaKernelMode = options.cudaKernelMode;
	summary.device = options.device;
	summary.deviceName = arena.deviceName;
	summary.freeBytes = arena.freeBytes;
	summary.totalBytes = arena.totalBytes;
	summary.candidateRecords = layout.candidates.size();
	summary.targetGroups = layout.groups.size();
	summary.filteredPositions = layout.totalFilteredPositions;

	size_t candidateBytes =
		checkedBytes(layout.candidates.size(), sizeof(CandidateRecord), "packed candidates");
	size_t groupBytes =
		checkedBytes(layout.groups.size(), sizeof(TargetGroup), "packed target groups");
	size_t paramsBytes =
		checkedBytes(layout.params.size(), sizeof(DeviceParams), "packed params");
	size_t tableBytes = checkedBytes(layout.candidates.size(), sizeof(int32_t),
									"packed DP table");
	size_t usedBytes = checkedBytes(layout.candidates.size(), sizeof(uint8_t),
								   "packed ordered flags");
	size_t outputBytes = checkedBytes(layout.groups.size(), sizeof(DeviceOverlap),
									 "packed output overlaps");
	summary.requiredBytes = candidateBytes + groupBytes + paramsBytes +
							tableBytes * 2 + usedBytes + outputBytes;
	if (options.hasMemoryBudget && summary.requiredBytes > options.memoryBudgetBytes)
	{
		throw std::runtime_error("CUDA packed overlap replay memory budget exceeded: required=" +
								 std::to_string(summary.requiredBytes) +
								 " budget=" + std::to_string(options.memoryBudgetBytes));
	}

	size_t allocationsBefore = arena.allocations;
	size_t reusesBefore = arena.reuses;
	auto allocStart = Clock::now();
	ensureArenaBuffer(arena.candidates, candidateBytes, "packed candidates", arena);
	ensureArenaBuffer(arena.groups, groupBytes, "packed target groups", arena);
	ensureArenaBuffer(arena.params, paramsBytes, "packed params", arena);
	ensureArenaBuffer(arena.scores, tableBytes, "packed score table", arena);
	ensureArenaBuffer(arena.backtrack, tableBytes, "packed backtrack table", arena);
	ensureArenaBuffer(arena.used, usedBytes, "packed ordered flags", arena);
	ensureArenaBuffer(arena.output, outputBytes, "packed output overlaps", arena);
	auto allocEnd = Clock::now();
	summary.deviceAllocationMs = elapsedMs(allocStart, allocEnd);
	summary.arenaAllocations = arena.allocations - allocationsBefore;
	summary.arenaReuses = arena.reuses - reusesBefore;
	summary.arenaCapacityBytes = arena.capacityBytes();

	auto h2dStart = Clock::now();
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(arena.candidates.get(), layout.candidates.data(), candidateBytes,
				   cudaMemcpyHostToDevice),
		"copy packed candidates to device");
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(arena.groups.get(), layout.groups.data(), groupBytes,
				   cudaMemcpyHostToDevice),
		"copy packed target groups to device");
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(arena.params.get(), layout.params.data(), paramsBytes,
				   cudaMemcpyHostToDevice),
		"copy packed params to device");
	auto h2dEnd = Clock::now();
	summary.hostToDeviceMs = elapsedMs(h2dStart, h2dEnd);

	DeviceParams defaultParams{};
	auto kernelStart = Clock::now();
	if (options.cudaKernelMode == "serial")
	{
		overlapChainKernel<<<static_cast<unsigned int>(layout.groups.size()), 1>>>(
			arena.candidates.get(),
			arena.groups.get(),
			static_cast<uint32_t>(layout.groups.size()),
			nullptr,
			0,
			defaultParams,
			arena.params.get(),
			arena.scores.get(),
			arena.backtrack.get(),
			arena.used.get(),
			arena.output.get());
	}
	else
	{
		overlapChainReduceKernel<<<static_cast<unsigned int>(layout.groups.size()),
								   OVERLAP_CHAIN_REDUCE_THREADS>>>(
			arena.candidates.get(),
			arena.groups.get(),
			static_cast<uint32_t>(layout.groups.size()),
			nullptr,
			0,
			defaultParams,
			arena.params.get(),
			arena.scores.get(),
			arena.backtrack.get(),
			arena.used.get(),
			arena.output.get());
	}
	cuflye::cuda_raii::checkCuda(cudaGetLastError(), "launch packed overlap chain kernel");
	cuflye::cuda_raii::checkCuda(cudaDeviceSynchronize(),
								 "synchronize packed overlap chain kernel");
	auto kernelEnd = Clock::now();
	summary.kernelMs = elapsedMs(kernelStart, kernelEnd);
	summary.kernelLaunches = 1;

	std::vector<DeviceOverlap> deviceOverlaps(layout.groups.size());
	auto d2hStart = Clock::now();
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(deviceOverlaps.data(), arena.output.get(), outputBytes,
				   cudaMemcpyDeviceToHost),
		"copy packed overlaps to host");
	auto d2hEnd = Clock::now();
	summary.deviceToHostMs = elapsedMs(d2hStart, d2hEnd);

	outputs.clear();
	outputs.resize(fixtures.size());
	size_t outputRecords = 0;
	auto finalizeStart = Clock::now();
	for (size_t fixtureIndex = 0; fixtureIndex < fixtures.size(); ++fixtureIndex)
	{
		size_t begin = layout.groupOffsets[fixtureIndex];
		size_t end = fixtureIndex + 1 == fixtures.size() ?
			layout.groups.size() : layout.groupOffsets[fixtureIndex + 1];
		std::vector<DeviceOverlap> fixtureOverlaps(deviceOverlaps.begin() + begin,
												   deviceOverlaps.begin() + end);
		outputs[fixtureIndex] = finalizeOverlaps(fixtureOverlaps,
												 fixtures[fixtureIndex].manifest.params,
												 fixtures[fixtureIndex].filteredPositions);
		outputRecords += outputs[fixtureIndex].size();
	}
	auto finalizeEnd = Clock::now();
	summary.finalizeMs = elapsedMs(finalizeStart, finalizeEnd);
	summary.outputRecords = outputRecords;
	summary.totalBeforeJsonMs = summary.deviceAllocationMs +
								summary.hostToDeviceMs + summary.kernelMs +
								summary.deviceToHostMs + summary.finalizeMs;
	return summary;
}

std::vector<CudaRunSummary> runBatchOnce(const Options& options,
										 std::vector<LoadedFixture>& fixtures,
										 CudaOverlapArena& arena,
										 std::vector<std::vector<HostOverlap>>& outputs)
{
	outputs.clear();
	outputs.resize(fixtures.size());
	std::vector<CudaRunSummary> summaries;
	for (size_t index = 0; index < fixtures.size(); ++index)
	{
		if (options.backend == "cuda")
		{
			summaries.push_back(runCudaWithArena(options,
												fixtures[index].manifest,
												fixtures[index].candidates,
												fixtures[index].filteredPositions,
												fixtures[index].groups,
												arena,
												outputs[index]));
		}
		else
		{
			summaries.push_back(runCpu(fixtures[index].manifest,
									  fixtures[index].candidates,
									  fixtures[index].filteredPositions,
									  fixtures[index].groups,
									  outputs[index]));
		}
	}
	return summaries;
}

void writeBatchJson(const std::string& path,
					const Options& options,
					const std::vector<BatchFixtureOutput>& fixtures,
					const BatchJsonProvenance& provenance,
					double setupMs,
					double parseMs,
					double writeMs,
					double meanTotalMs,
					double minTotalMs,
					double maxTotalMs,
					double meanCoreMs,
					size_t arenaAllocations,
					size_t arenaReuses,
					size_t arenaCapacityBytes)
{
	ensureParentDirectory(path);
	std::ofstream output(path);
	if (!output)
	{
		throw std::runtime_error("cannot write batch JSON summary: " + path);
	}
	size_t totalCandidates = 0;
	size_t totalOverlaps = 0;
	for (const auto& fixture : fixtures)
	{
		totalCandidates += fixture.candidateRecords;
		totalOverlaps += fixture.outputRecords;
	}

	output << std::fixed << std::setprecision(6);
	output << "{\n"
		   << "  \"schema\": \"cuflye-overlap-replay-batch-worker-v0\",\n"
		   << "  \"status\": \"ok\",\n"
		   << "  \"backend\": \"" << options.backend << "\",\n"
		   << "  \"cuda_kernel_mode\": \"" << options.cudaKernelMode << "\",\n"
		   << "  \"batch_execution\": \"" << provenance.batchExecution << "\",\n"
		   << "  \"batch_fixtures_file\": \"" << jsonEscape(options.batchFixturesFile) << "\",\n"
		   << "  \"batch_output_dir\": \"" << jsonEscape(options.batchOutputDir) << "\",\n"
		   << "  \"fixture_count\": " << fixtures.size() << ",\n"
		   << "  \"total_candidate_records\": " << totalCandidates << ",\n"
		   << "  \"total_output_records\": " << totalOverlaps << ",\n"
		   << "  \"kernel_launches_per_timed_run\": "
		   << provenance.kernelLaunchesPerTimedRun << ",\n"
		   << "  \"packed_layout\": {\n"
		   << "    \"candidate_records\": " << provenance.packedCandidateRecords << ",\n"
		   << "    \"target_groups\": " << provenance.packedTargetGroups << ",\n"
		   << "    \"param_records\": " << provenance.packedParamRecords << ",\n"
		   << "    \"filtered_positions\": " << provenance.packedFilteredPositions << "\n"
		   << "  },\n"
		   << "  \"timing_ms\": {\n"
		   << "    \"setup\": " << setupMs << ",\n"
		   << "    \"parse\": " << parseMs << ",\n"
		   << "    \"write_output\": " << writeMs << ",\n"
		   << "    \"mean_total_before_write\": " << meanTotalMs << ",\n"
		   << "    \"min_total_before_write\": " << minTotalMs << ",\n"
		   << "    \"max_total_before_write\": " << maxTotalMs << ",\n"
		   << "    \"mean_core\": " << meanCoreMs << "\n"
		   << "  },\n"
		   << "  \"benchmark\": {\n"
		   << "    \"warmup_runs\": " << options.warmupRuns << ",\n"
		   << "    \"timed_runs\": " << options.benchmarkRuns << "\n"
		   << "  },\n"
		   << "  \"arena\": {\n"
		   << "    \"allocations\": " << arenaAllocations << ",\n"
		   << "    \"reuses\": " << arenaReuses << ",\n"
		   << "    \"capacity_bytes\": " << arenaCapacityBytes << "\n"
		   << "  },\n"
		   << "  \"fixtures\": [\n";
	for (size_t index = 0; index < fixtures.size(); ++index)
	{
		const auto& fixture = fixtures[index];
		output << "    {\n"
			   << "      \"name\": \"" << jsonEscape(fixture.name) << "\",\n"
			   << "      \"fixture_dir\": \"" << jsonEscape(fixture.fixtureDir) << "\",\n"
			   << "      \"output_tsv\": \"" << jsonEscape(fixture.outputTsv) << "\",\n"
			   << "      \"query_id\": " << fixture.queryId << ",\n"
			   << "      \"candidate_offset\": " << fixture.candidateOffset << ",\n"
			   << "      \"group_offset\": " << fixture.groupOffset << ",\n"
			   << "      \"params_index\": " << fixture.paramsIndex << ",\n"
			   << "      \"candidate_records\": " << fixture.candidateRecords << ",\n"
			   << "      \"target_groups\": " << fixture.targetGroups << ",\n"
			   << "      \"output_records\": " << fixture.outputRecords << ",\n";
		if (fixture.summary.timedRuns == 0)
		{
			output << "      \"mean_total_before_json_ms\": null,\n"
				   << "      \"mean_core_ms\": null,\n";
		}
		else
		{
			output << "      \"mean_total_before_json_ms\": "
				   << fixture.summary.benchmarkMeanTotalMs << ",\n"
				   << "      \"mean_core_ms\": " << fixture.summary.benchmarkMeanCoreMs << ",\n";
		}
		output
			   << "      \"arena_allocations\": " << fixture.summary.arenaAllocations << ",\n"
			   << "      \"arena_reuses\": " << fixture.summary.arenaReuses << "\n"
			   << "    }" << (index + 1 == fixtures.size() ? "\n" : ",\n");
	}
	output << "  ]\n"
		   << "}\n";
}

PackedBatchRunResult runPackedBatchWithArena(const Options& options,
											 const std::vector<LoadedFixture>& fixtures,
											 double parseMs,
											 CudaOverlapArena& arena)
{
	auto layoutStart = Clock::now();
	PackedBatchLayout layout = buildPackedBatchLayout(fixtures);
	auto layoutEnd = Clock::now();
	double parseAndLayoutMs = parseMs + elapsedMs(layoutStart, layoutEnd);

	ensureDirectory(options.batchOutputDir);
	size_t allocationsBefore = arena.allocations;
	size_t reusesBefore = arena.reuses;
	auto setupStart = Clock::now();
	initializeArena(options, arena);
	auto setupEnd = Clock::now();
	double setupMs = elapsedMs(setupStart, setupEnd);

	std::vector<std::vector<HostOverlap>> outputs;
	for (uint32_t index = 0; index < options.warmupRuns; ++index)
	{
		(void)runPackedCudaBatchOnce(options, fixtures, layout, arena, outputs);
	}

	std::vector<CudaRunSummary> timedSummaries;
	for (uint32_t run = 0; run < options.benchmarkRuns; ++run)
	{
		timedSummaries.push_back(runPackedCudaBatchOnce(options, fixtures, layout,
														arena, outputs));
	}

	double totalSum = 0.0;
	double coreSum = 0.0;
	double minTotal = timedSummaries.front().totalBeforeJsonMs;
	double maxTotal = timedSummaries.front().totalBeforeJsonMs;
	for (const auto& summary : timedSummaries)
	{
		totalSum += summary.totalBeforeJsonMs;
		coreSum += summary.kernelMs;
		minTotal = std::min(minTotal, summary.totalBeforeJsonMs);
		maxTotal = std::max(maxTotal, summary.totalBeforeJsonMs);
	}
	double meanTotal = totalSum / static_cast<double>(timedSummaries.size());
	double meanCore = coreSum / static_cast<double>(timedSummaries.size());
	CudaRunSummary lastSummary = timedSummaries.back();

	std::vector<BatchFixtureOutput> fixtureOutputs;
	auto writeStart = Clock::now();
	for (size_t index = 0; index < fixtures.size(); ++index)
	{
		std::string fixtureOutDir = joinPath(options.batchOutputDir, fixtures[index].name);
		ensureDirectory(fixtureOutDir);
		std::string outputTsv = joinPath(fixtureOutDir, "overlaps.tsv");
		writeOverlaps(outputTsv, outputs[index]);
		size_t groupEnd = index + 1 == fixtures.size() ?
			layout.groups.size() : layout.groupOffsets[index + 1];
		CudaRunSummary fixtureSummary;
		fixtureSummary.backend = "cuda";
		fixtureSummary.cudaKernelMode = options.cudaKernelMode;
		fixtureOutputs.push_back({
			fixtures[index].fixtureDir,
			fixtures[index].name,
			outputTsv,
			fixtures[index].manifest.queryId,
			layout.candidateOffsets[index],
			layout.groupOffsets[index],
			index,
			fixtures[index].candidates.size(),
			groupEnd - layout.groupOffsets[index],
			outputs[index].size(),
			fixtureSummary
		});
	}
	auto writeEnd = Clock::now();
	double writeMs = elapsedMs(writeStart, writeEnd);

	BatchJsonProvenance provenance;
	provenance.batchExecution = options.batchExecution;
	provenance.kernelLaunchesPerTimedRun = lastSummary.kernelLaunches;
	provenance.packedCandidateRecords = layout.candidates.size();
	provenance.packedTargetGroups = layout.groups.size();
	provenance.packedParamRecords = layout.params.size();
	provenance.packedFilteredPositions = layout.totalFilteredPositions;

	writeBatchJson(options.batchJsonOutput, options, fixtureOutputs, provenance,
				   setupMs, parseAndLayoutMs, writeMs, meanTotal, minTotal,
				   maxTotal, meanCore, arena.allocations, arena.reuses,
				   arena.capacityBytes());

	PackedBatchRunResult result;
	result.setupMs = setupMs;
	result.parseMs = parseAndLayoutMs;
	result.writeMs = writeMs;
	result.meanTotalMs = meanTotal;
	result.minTotalMs = minTotal;
	result.maxTotalMs = maxTotal;
	result.meanCoreMs = meanCore;
	result.fixtureCount = fixtures.size();
	result.outputRecords = lastSummary.outputRecords;
	result.arenaAllocations = arena.allocations - allocationsBefore;
	result.arenaReuses = arena.reuses - reusesBefore;
	result.arenaCapacityBytes = arena.capacityBytes();
	result.provenance = provenance;
	return result;
}

int runPackedBatchMain(const Options& options,
					   const std::vector<LoadedFixture>& fixtures,
					   double parseMs)
{
	CudaOverlapArena arena;
	(void)runPackedBatchWithArena(options, fixtures, parseMs, arena);
	return 0;
}

int runBatchMain(const Options& options)
{
	auto parseStart = Clock::now();
	std::vector<std::string> fixtureDirs = loadFixtureList(options.batchFixturesFile);
	std::vector<LoadedFixture> fixtures;
	for (const auto& fixtureDir : fixtureDirs)
	{
		fixtures.push_back(loadFixture(fixtureDir));
	}
	auto parseEnd = Clock::now();
	double parseMs = elapsedMs(parseStart, parseEnd);
	if (options.batchExecution == "packed")
	{
		return runPackedBatchMain(options, fixtures, parseMs);
	}

	ensureDirectory(options.batchOutputDir);
	CudaOverlapArena arena;
	double setupMs = 0.0;
	if (options.backend == "cuda")
	{
		auto setupStart = Clock::now();
		initializeArena(options, arena);
		auto setupEnd = Clock::now();
		setupMs = elapsedMs(setupStart, setupEnd);
	}

	std::vector<std::vector<HostOverlap>> outputs;
	for (uint32_t index = 0; index < options.warmupRuns; ++index)
	{
		(void)runBatchOnce(options, fixtures, arena, outputs);
	}

	std::vector<double> timedTotals;
	std::vector<double> timedCores;
	std::vector<double> fixtureTotalSums(fixtures.size(), 0.0);
	std::vector<double> fixtureCoreSums(fixtures.size(), 0.0);
	std::vector<CudaRunSummary> lastSummaries;
	for (uint32_t run = 0; run < options.benchmarkRuns; ++run)
	{
		std::vector<CudaRunSummary> summaries =
			runBatchOnce(options, fixtures, arena, outputs);
		double total = 0.0;
		double core = 0.0;
		for (size_t index = 0; index < summaries.size(); ++index)
		{
			const auto& summary = summaries[index];
			total += summary.totalBeforeJsonMs;
			core += coreMs(summary);
			fixtureTotalSums[index] += summary.totalBeforeJsonMs;
			fixtureCoreSums[index] += coreMs(summary);
		}
		timedTotals.push_back(total);
		timedCores.push_back(core);
		lastSummaries = summaries;
	}

	double totalSum = 0.0;
	double coreSum = 0.0;
	double minTotal = timedTotals.front();
	double maxTotal = timedTotals.front();
	for (size_t index = 0; index < timedTotals.size(); ++index)
	{
		totalSum += timedTotals[index];
		coreSum += timedCores[index];
		minTotal = std::min(minTotal, timedTotals[index]);
		maxTotal = std::max(maxTotal, timedTotals[index]);
	}
	double meanTotal = totalSum / static_cast<double>(timedTotals.size());
	double meanCore = coreSum / static_cast<double>(timedCores.size());

	std::vector<BatchFixtureOutput> fixtureOutputs;
	auto writeStart = Clock::now();
	for (size_t index = 0; index < fixtures.size(); ++index)
	{
		std::string fixtureOutDir = joinPath(options.batchOutputDir, fixtures[index].name);
		ensureDirectory(fixtureOutDir);
		std::string outputTsv = joinPath(fixtureOutDir, "overlaps.tsv");
		writeOverlaps(outputTsv, outputs[index]);
		CudaRunSummary summary = lastSummaries[index];
		summary.warmupRuns = options.warmupRuns;
		summary.timedRuns = options.benchmarkRuns;
		summary.benchmarkMeanTotalMs =
			fixtureTotalSums[index] / static_cast<double>(options.benchmarkRuns);
		summary.benchmarkMeanCoreMs =
			fixtureCoreSums[index] / static_cast<double>(options.benchmarkRuns);
		fixtureOutputs.push_back({
			fixtures[index].fixtureDir,
			fixtures[index].name,
			outputTsv,
			fixtures[index].manifest.queryId,
			0,
			0,
			0,
			fixtures[index].candidates.size(),
			fixtures[index].groups.size(),
			outputs[index].size(),
			summary
		});
	}
	auto writeEnd = Clock::now();
	double writeMs = elapsedMs(writeStart, writeEnd);

	BatchJsonProvenance provenance;
	provenance.batchExecution = options.batchExecution;
	provenance.kernelLaunchesPerTimedRun = options.backend == "cuda" ? fixtures.size() : 0;
	for (const auto& fixture : fixtures)
	{
		provenance.packedCandidateRecords += fixture.candidates.size();
		provenance.packedTargetGroups += fixture.groups.size();
		provenance.packedFilteredPositions += fixture.filteredPositions.size();
	}
	provenance.packedParamRecords = fixtures.size();

	writeBatchJson(options.batchJsonOutput, options, fixtureOutputs, provenance,
				   setupMs, parseMs, writeMs, meanTotal, minTotal, maxTotal, meanCore,
				   arena.allocations, arena.reuses, arena.capacityBytes());
	return 0;
}

OverlapWorkerRequest parseOverlapWorkerRequestObject(const std::string& text)
{
	std::map<std::string, std::string> fields = parseFlatJsonObject(text);
	OverlapWorkerRequest request;
	request.schema = requireJsonField(fields, "schema");
	request.requestId = requireJsonField(fields, "request_id");
	request.responseJson = requireJsonField(fields, "response_json");
	request.adapterMode = requireJsonField(fields, "adapter_mode");
	request.overlapAbi = requireJsonField(fields, "overlap_abi");
	request.options.backend = requireJsonField(fields, "backend");
	request.options.batchExecution = requireJsonField(fields, "batch_execution");
	request.options.cudaKernelMode = requireJsonField(fields, "cuda_kernel_mode");
	request.options.device = parseWorkerInt(requireJsonField(fields, "device"), "device");
	request.options.batchFixturesFile = requireJsonField(fields, "batch_fixtures_file");
	request.options.batchOutputDir = requireJsonField(fields, "batch_output_dir");
	request.options.batchJsonOutput = requireJsonField(fields, "batch_json_output");

	std::string warmupRuns = optionalJsonField(fields, "warmup_runs");
	if (!warmupRuns.empty() && warmupRuns != "null")
	{
		request.options.warmupRuns = parseWorkerUInt32(warmupRuns, "warmup_runs");
	}
	std::string benchmarkRuns = optionalJsonField(fields, "benchmark_runs");
	if (!benchmarkRuns.empty() && benchmarkRuns != "null")
	{
		request.options.benchmarkRuns = parseWorkerUInt32(benchmarkRuns, "benchmark_runs");
	}
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
		request.expectedFixtureCount = static_cast<size_t>(
			parseWorkerUnsigned(expectedFixtureCount, "expected_fixture_count"));
	}
	return request;
}

std::vector<OverlapWorkerRequest> loadOverlapWorkerRequests(const Options& cliOptions)
{
	std::vector<OverlapWorkerRequest> requests;
	if (!cliOptions.workerRequestJson.empty())
	{
		requests.push_back(parseOverlapWorkerRequestObject(
			readTextFile(cliOptions.workerRequestJson)));
		return requests;
	}

	std::ifstream input(cliOptions.workerRequestsJsonl);
	if (!input)
	{
		throw std::runtime_error("cannot read overlap worker requests JSONL: " +
								 cliOptions.workerRequestsJsonl);
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
			requests.push_back(parseOverlapWorkerRequestObject(stripped));
		}
		catch (const std::exception& exc)
		{
			throw std::runtime_error(cliOptions.workerRequestsJsonl + ":" +
									 std::to_string(lineNumber) + ": " + exc.what());
		}
	}
	if (requests.size() < 2)
	{
		throw std::runtime_error("--worker-requests-jsonl proof mode requires at least two requests");
	}
	return requests;
}

void validateOverlapWorkerRequest(const OverlapWorkerRequest& request)
{
	if (request.schema != "cuflye-overlap-worker-request-v0")
	{
		throw std::runtime_error("unsupported overlap worker request schema");
	}
	if (request.adapterMode != "overlap-replay-batch-v0")
	{
		throw std::runtime_error("unsupported overlap worker adapter_mode");
	}
	if (request.overlapAbi != "overlap-range-v1")
	{
		throw std::runtime_error("unsupported overlap worker overlap_abi");
	}
	if (request.options.backend != "cuda")
	{
		throw std::runtime_error("unsupported overlap worker backend");
	}
	if (request.options.batchExecution != "packed")
	{
		throw std::runtime_error("unsupported overlap worker batch_execution");
	}
	if (request.options.cudaKernelMode != "serial" &&
		request.options.cudaKernelMode != "parallel-reduce")
	{
		throw std::runtime_error("unsupported overlap worker cuda_kernel_mode");
	}
	if (request.options.benchmarkRuns == 0)
	{
		throw std::runtime_error("overlap worker benchmark_runs must be greater than zero");
	}
}

void validateOverlapWorkerRequestSet(const std::vector<OverlapWorkerRequest>& requests)
{
	if (requests.empty()) throw std::runtime_error("overlap worker request set is empty");
	int device = requests.front().options.device;
	for (const auto& request : requests)
	{
		if (request.options.device != device)
		{
			throw std::runtime_error("overlap worker requires all requests to use one CUDA device");
		}
	}
}

std::vector<LoadedFixture> loadWorkerFixtures(const OverlapWorkerRequest& request,
											  double& parseMs)
{
	auto parseStart = Clock::now();
	std::vector<std::string> fixtureDirs =
		loadFixtureList(request.options.batchFixturesFile);
	if (request.hasExpectedFixtureCount &&
		fixtureDirs.size() != request.expectedFixtureCount)
	{
		throw std::runtime_error("overlap worker expected fixture count mismatch");
	}
	std::vector<LoadedFixture> fixtures;
	for (const auto& fixtureDir : fixtureDirs)
	{
		fixtures.push_back(loadFixture(fixtureDir));
	}
	auto parseEnd = Clock::now();
	parseMs = elapsedMs(parseStart, parseEnd);
	return fixtures;
}

std::string buildOverlapWorkerResponseJson(const OverlapWorkerRequest& request,
										   const PackedBatchRunResult& result,
										   size_t requestOrdinal,
										   bool workerContextWarm,
										   double workerContextSetupMs,
										   double workerUptimeMs,
										   double requestTotalMs)
{
	double timedBackendTotal = result.meanTotalMs *
		static_cast<double>(request.options.benchmarkRuns);
	double workerOverhead = std::max(0.0, requestTotalMs - timedBackendTotal);
	std::ostringstream json;
	json << std::fixed << std::setprecision(6);
	json << "{\n"
		 << "  \"schema\": \"cuflye-overlap-worker-response-v0\",\n"
		 << "  \"request_id\": \"" << jsonEscape(request.requestId) << "\",\n"
		 << "  \"status\": \"ok\",\n"
		 << "  \"request_ordinal\": " << requestOrdinal << ",\n"
		 << "  \"worker_cuda_context_warm\": "
		 << (workerContextWarm ? "true" : "false") << ",\n"
		 << "  \"worker_context_setup_ms\": " << workerContextSetupMs << ",\n"
		 << "  \"worker_device_arena_enabled\": true,\n"
		 << "  \"worker_device_arena_allocations\": " << result.arenaAllocations << ",\n"
		 << "  \"worker_device_arena_reuses\": " << result.arenaReuses << ",\n"
		 << "  \"worker_device_arena_capacity_bytes\": "
		 << result.arenaCapacityBytes << ",\n"
		 << "  \"adapter_mode\": \"overlap-replay-batch-v0\",\n"
		 << "  \"overlap_abi\": \"overlap-range-v1\",\n"
		 << "  \"batch_execution\": \"" << jsonEscape(request.options.batchExecution) << "\",\n"
		 << "  \"cuda_kernel_mode\": \"" << jsonEscape(request.options.cudaKernelMode) << "\",\n"
		 << "  \"fixture_count\": " << result.fixtureCount << ",\n"
		 << "  \"output_records\": " << result.outputRecords << ",\n"
		 << "  \"kernel_launches_per_timed_run\": "
		 << result.provenance.kernelLaunchesPerTimedRun << ",\n"
		 << "  \"batch_json_output\": \""
		 << jsonEscape(request.options.batchJsonOutput) << "\",\n"
		 << "  \"batch_output_dir\": \""
		 << jsonEscape(request.options.batchOutputDir) << "\",\n"
		 << "  \"timing_ms\": {\n"
		 << "    \"worker_uptime\": " << workerUptimeMs << ",\n"
		 << "    \"request_total\": " << requestTotalMs << ",\n"
		 << "    \"backend_mean_total_before_write\": " << result.meanTotalMs << ",\n"
		 << "    \"backend_timed_total_before_write\": " << timedBackendTotal << ",\n"
		 << "    \"worker_overhead\": " << workerOverhead << ",\n"
		 << "    \"parse\": " << result.parseMs << ",\n"
		 << "    \"write_output\": " << result.writeMs << ",\n"
		 << "    \"kernel\": " << result.meanCoreMs << "\n"
		 << "  }\n"
		 << "}\n";
	return json.str();
}

std::string buildOverlapWorkerErrorJson(const OverlapWorkerRequest& request,
										size_t requestOrdinal,
										const std::string& message)
{
	std::ostringstream json;
	json << "{\n"
		 << "  \"schema\": \"cuflye-overlap-worker-response-v0\",\n"
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

void emitOverlapWorkerResponse(const std::string& path, const std::string& response)
{
	writeTextFile(path, response);
	std::cout << response;
}

int runOverlapWorkerMain(const Options& cliOptions)
{
	std::vector<OverlapWorkerRequest> requests = loadOverlapWorkerRequests(cliOptions);
	validateOverlapWorkerRequestSet(requests);

	CudaOverlapArena arena;
	auto workerStart = Clock::now();
	auto contextStart = Clock::now();
	initializeArena(requests.front().options, arena);
	auto contextEnd = Clock::now();
	double workerContextSetupMs = elapsedMs(contextStart, contextEnd);

	for (size_t index = 0; index < requests.size(); ++index)
	{
		const auto& request = requests[index];
		size_t requestOrdinal = index + 1;
		bool workerContextWarm = requestOrdinal > 1;
		auto requestStart = Clock::now();
		try
		{
			validateOverlapWorkerRequest(request);
			double parseMs = 0.0;
			std::vector<LoadedFixture> fixtures = loadWorkerFixtures(request, parseMs);
			PackedBatchRunResult result =
				runPackedBatchWithArena(request.options, fixtures, parseMs, arena);
			double requestTotalMs = elapsedMs(requestStart, Clock::now());
			double workerUptimeMs = elapsedMs(workerStart, Clock::now());
			std::string response = buildOverlapWorkerResponseJson(request, result,
																  requestOrdinal,
																  workerContextWarm,
																  workerContextSetupMs,
																  workerUptimeMs,
																  requestTotalMs);
			emitOverlapWorkerResponse(request.responseJson, response);
		}
		catch (const std::exception& exc)
		{
			std::string response = buildOverlapWorkerErrorJson(request, requestOrdinal,
															  exc.what());
			emitOverlapWorkerResponse(request.responseJson, response);
			return 1;
		}
	}
	return 0;
}
}

int main(int argc, char** argv)
{
	try
	{
		Options options = parseArgs(argc, argv);
		if (!options.workerRequestJson.empty() || !options.workerRequestsJsonl.empty())
		{
			return runOverlapWorkerMain(options);
		}
		if (!options.batchFixturesFile.empty())
		{
			return runBatchMain(options);
		}
		auto parseStart = Clock::now();
		LoadedFixture fixture = loadFixture(options.fixtureDir);
		auto parseEnd = Clock::now();

		std::vector<HostOverlap> overlaps;
		CudaRunSummary summary;
		if (options.backend == "cuda")
		{
			summary = runCudaBenchmark(options, fixture.manifest, fixture.candidates,
									   fixture.filteredPositions, fixture.groups, overlaps);
		}
		else
		{
			summary = runCpuBenchmark(options, fixture.manifest, fixture.candidates,
									  fixture.filteredPositions, fixture.groups, overlaps);
		}
		summary.parseMs = elapsedMs(parseStart, parseEnd);
		auto writeStart = Clock::now();
		writeOverlaps(options.outputTsv, overlaps);
		auto writeEnd = Clock::now();
		summary.writeMs = elapsedMs(writeStart, writeEnd);
		summary.totalBeforeJsonMs += summary.parseMs + summary.writeMs;
		writeJsonSummary(options.jsonOutput, options, fixture.manifest, summary);
		return 0;
	}
	catch (const std::exception& exc)
	{
		std::cerr << "CUDA overlap chain replay failed: " << exc.what() << "\n";
		return 1;
	}
}
