// SPDX-License-Identifier: BSD-3-Clause

#include <cuda_runtime_api.h>

#include "cuflye_cuda_raii.hpp"

#include <algorithm>
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
	int32_t padding;
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
	std::string backend = "cuda";
	std::string cudaKernelMode = "serial";
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
								   int32_t* scoreTable,
								   int32_t* backtrackTable,
								   uint8_t* orderedUsed,
								   DeviceOverlap* output)
{
	uint32_t groupId = blockIdx.x;
	if (groupId >= groupCount || threadIdx.x != 0) return;

	TargetGroup group = groups[groupId];
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
		params.minKmerSurvivalRate * static_cast<float>(params.minimumOverlap))
	{
		return;
	}

	if (group.maxCur - group.minCur < params.minimumOverlap ||
		group.maxExt - group.minExt < params.minimumOverlap)
	{
		return;
	}
	if (params.checkOverhang && !params.forceLocal)
	{
		if (min(group.minCur, group.minExt) > params.maximumOverhang) return;
		if (min(params.queryLen - group.maxCur, group.targetLen - group.maxExt) >
			params.maximumOverhang)
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
			if (0 < curDelta && curDelta < params.maximumJump &&
				0 < extDelta && extDelta < params.maximumJump &&
				jumpDiv <= params.maxGap)
			{
				int32_t matchScore = min(min(curDelta, extDelta), params.kmerSize);
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

		scoreTable[start + i] = max(maxScore, params.kmerSize);
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

		if (!overlapTest(overlap, params)) continue;
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
			params.minKmerSurvivalRate * static_cast<float>(params.minimumOverlap))
		{
			skipGroup = 1;
		}
		if (group.maxCur - group.minCur < params.minimumOverlap ||
			group.maxExt - group.minExt < params.minimumOverlap)
		{
			skipGroup = 1;
		}
		if (params.checkOverhang && !params.forceLocal)
		{
			if (min(group.minCur, group.minExt) > params.maximumOverhang) skipGroup = 1;
			if (min(params.queryLen - group.maxCur, group.targetLen - group.maxExt) >
				params.maximumOverhang)
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
				if (0 < curDelta && curDelta < params.maximumJump &&
					0 < extDelta && extDelta < params.maximumJump &&
					jumpDiv <= params.maxGap)
				{
					int32_t matchScore = min(min(curDelta, extDelta), params.kmerSize);
					float gapPenalty = jumpDiv > params.gapJumpThreshold ?
						params.largeGapPenalty : params.smallGapPenalty;
					int32_t gapCost =
						static_cast<int32_t>(gapPenalty * static_cast<float>(jumpDiv));
					int32_t nextScore = scoreTable[start + j] + matchScore - gapCost;
					if (nextScore > maxScore)
					{
						maxScore = nextScore;
						if (jumpDiv == 0 && curDelta < params.kmerSize)
						{
							breakJ = j;
							break;
						}
					}
				}
				if (group.extSorted && extNext - extPrev > params.maximumJump) break;
				if (!group.extSorted && curNext - curPrev > params.maximumJump) break;
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
			if (0 < curDelta && curDelta < params.maximumJump &&
				0 < extDelta && extDelta < params.maximumJump &&
				jumpDiv <= params.maxGap)
			{
				int32_t matchScore = min(min(curDelta, extDelta), params.kmerSize);
				float gapPenalty = jumpDiv > params.gapJumpThreshold ?
					params.largeGapPenalty : params.smallGapPenalty;
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
			scoreTable[start + i] = max(sharedScore[0], params.kmerSize);
			if (sharedScore[0] > params.kmerSize)
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

			if (!overlapTest(overlap, params)) continue;
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
		else if (arg == "--backend") options.backend = requireValue(arg);
		else if (arg == "--cuda-kernel-mode") options.cudaKernelMode = requireValue(arg);
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
					  << "[--backend cpu|cuda] [--device ID] "
					  << "[--cuda-kernel-mode serial|parallel-reduce] "
					  << "[--warmup-runs N] [--benchmark-runs N] "
					  << "[--memory-budget-bytes N]\n";
			std::exit(0);
		}
		else
		{
			throw std::runtime_error("unknown option: " + arg);
		}
	}
	if (options.fixtureDir.empty()) throw std::runtime_error("--fixture-dir is required");
	if (options.outputTsv.empty()) throw std::runtime_error("--output-tsv is required");
	if (options.jsonOutput.empty()) throw std::runtime_error("--json-output is required");
	if (options.backend != "cuda" && options.backend != "cpu")
	{
		throw std::runtime_error("--backend must be cpu or cuda");
	}
	if (options.cudaKernelMode != "serial" && options.cudaKernelMode != "parallel-reduce")
	{
		throw std::runtime_error("--cuda-kernel-mode must be serial or parallel-reduce");
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
			dScores.get(),
			dBacktrack.get(),
			dUsed.get(),
			dOutput.get());
	}
	cuflye::cuda_raii::checkCuda(cudaGetLastError(), "launch overlap chain kernel");
	cuflye::cuda_raii::checkCuda(cudaDeviceSynchronize(), "synchronize overlap chain kernel");
	auto kernelEnd = Clock::now();
	summary.kernelMs = elapsedMs(kernelStart, kernelEnd);

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
		   << "  \"supported_shape\": {\n"
		   << "    \"nucl_alignment\": false,\n"
		   << "    \"partition_bad_mappings\": false,\n"
		   << "    \"keep_alignment\": false,\n"
		   << "    \"only_max_ext\": true\n"
		   << "  }\n"
		   << "}\n";
}
}

int main(int argc, char** argv)
{
	try
	{
		Options options = parseArgs(argc, argv);
		auto parseStart = Clock::now();
		FixtureManifest manifest = loadManifest(options.fixtureDir);
		requireSupportedShape(manifest);

		std::vector<CandidateRecord> candidates =
			loadCandidates(joinPath(options.fixtureDir, manifest.files.candidates),
						   manifest.queryId);
		std::vector<int32_t> filteredPositions =
			loadFilteredPositions(joinPath(options.fixtureDir,
										   manifest.files.filteredPositions));
		std::map<int64_t, int32_t> targets =
			loadTargets(joinPath(options.fixtureDir, manifest.files.targets));
		if (candidates.size() != manifest.expectedCandidateRecords)
		{
			throw std::runtime_error("candidate record count does not match manifest");
		}
		if (targets.size() != manifest.expectedTargetRecords)
		{
			throw std::runtime_error("target record count does not match manifest");
		}
		std::vector<TargetGroup> groups =
			buildGroups(candidates, targets, manifest.queryLength);
		auto parseEnd = Clock::now();

		std::vector<HostOverlap> overlaps;
		CudaRunSummary summary;
		if (options.backend == "cuda")
		{
			summary = runCudaBenchmark(options, manifest, candidates,
									   filteredPositions, groups, overlaps);
		}
		else
		{
			summary = runCpuBenchmark(options, manifest, candidates,
									  filteredPositions, groups, overlaps);
		}
		summary.parseMs = elapsedMs(parseStart, parseEnd);
		auto writeStart = Clock::now();
		writeOverlaps(options.outputTsv, overlaps);
		auto writeEnd = Clock::now();
		summary.writeMs = elapsedMs(writeStart, writeEnd);
		summary.totalBeforeJsonMs += summary.parseMs + summary.writeMs;
		writeJsonSummary(options.jsonOutput, options, manifest, summary);
		return 0;
	}
	catch (const std::exception& exc)
	{
		std::cerr << "CUDA overlap chain replay failed: " << exc.what() << "\n";
		return 1;
	}
}
