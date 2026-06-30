// SPDX-License-Identifier: BSD-3-Clause

#include <cuda_runtime_api.h>

#include "cuflye_cuda_raii.hpp"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
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
	std::string backend = "cuda";
	int device = 0;
	uint32_t warmupRuns = 0;
	uint32_t benchmarkRuns = 1;
	bool hasMemoryBudget = false;
	unsigned long long memoryBudgetBytes = 0;
};

struct RunSummary
{
	std::string backend;
	double setupMs = 0.0;
	double deviceAllocationMs = 0.0;
	double hostToDeviceMs = 0.0;
	double kernelMs = 0.0;
	double cpuChainMs = 0.0;
	double deviceToHostMs = 0.0;
	double finalizeMs = 0.0;
	double writeMs = 0.0;
	double totalBeforeJsonMs = 0.0;
	double benchmarkMeanTotalMs = 0.0;
	double benchmarkMinTotalMs = 0.0;
	double benchmarkMaxTotalMs = 0.0;
	double benchmarkMeanCoreMs = 0.0;
	uint32_t warmupRuns = 0;
	uint32_t timedRuns = 0;
	size_t inputRecords = 0;
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

struct CpuChain
{
	std::vector<int32_t> indices;
	int32_t score = 0;
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

std::string jsonEscape(const std::string& text)
{
	std::ostringstream escaped;
	for (char ch : text)
	{
		switch (ch)
		{
		case '\\': escaped << "\\\\"; break;
		case '"': escaped << "\\\""; break;
		case '\n': escaped << "\\n"; break;
		case '\r': escaped << "\\r"; break;
		case '\t': escaped << "\\t"; break;
		default: escaped << ch; break;
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

std::vector<std::string> splitTabs(const std::string& line)
{
	std::vector<std::string> fields;
	std::string field;
	std::stringstream stream(line);
	while (std::getline(stream, field, '\t')) fields.push_back(field);
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
	while (value < text.size() &&
		   std::isspace(static_cast<unsigned char>(text[value])))
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
	manifest.alignmentInputRecords =
		static_cast<int32_t>(jsonInt(text, "alignment_input_records"));
	manifest.candidateChains = static_cast<int32_t>(jsonInt(text, "candidate_chains"));
	manifest.oracleChains = static_cast<int32_t>(jsonInt(text, "oracle_chains"));
	manifest.params.maximumJump = static_cast<int32_t>(jsonInt(text, "maximum_jump"));
	manifest.params.maxReadOverlap = static_cast<int32_t>(jsonInt(text, "max_read_overlap"));
	manifest.params.minimumOverlap = static_cast<int32_t>(jsonInt(text, "minimum_overlap"));
	manifest.params.maxSeparation = static_cast<int32_t>(jsonInt(text, "max_separation"));
	manifest.readsBaseAlignment = jsonBool(text, "reads_base_alignment");
	return manifest;
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

LoadedFixture loadFixture(const std::string& fixtureDir)
{
	LoadedFixture fixture;
	fixture.fixtureDir = fixtureDir;
	fixture.manifest = loadManifest(fixtureDir);
	fixture.overlaps =
		loadEdgeOverlaps(joinPath(fixtureDir, "edge-overlaps.tsv"), fixture.manifest.queryId);
	fixture.divergenceAccepted =
		loadDivergenceAccepted(joinPath(fixtureDir, "chain-divergence.tsv"));
	if (fixture.overlaps.size() !=
		static_cast<size_t>(fixture.manifest.alignmentInputRecords))
	{
		throw std::runtime_error("edge-overlap count does not match manifest");
	}
	if (fixture.overlaps.size() > MAX_REPLAY_RECORDS)
	{
		throw std::runtime_error("fixture exceeds M5c bounded CUDA replay record limit");
	}
	return fixture;
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
		bool canBeExtended = edgeAlignment.edgeLen - edgeAlignment.edgeEnd <
							 params.maximumJump;

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
	std::stable_sort(active.begin(), active.end(),
					 [](const CpuChain& lhs, const CpuChain& rhs)
					 {
						 return lhs.score > rhs.score;
					 });

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
			int32_t overlapRate =
				std::min(last.readEnd, existingLast.readEnd) -
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

std::vector<OutputSegment> buildSegmentsFromCpuChains(
	const std::vector<CpuChain>& chains,
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

__global__ void readAlignmentChainKernel(const EdgeOverlap* overlaps,
										 int32_t overlapCount,
										 const uint8_t* divergenceAccepted,
										 int32_t divergenceCount,
										 ReplayParams params,
										 ChainRecord* chains,
										 int32_t* activeIds,
										 int32_t* frozenIds,
										 int32_t* orderedIds,
										 int32_t* acceptedIds,
										 int32_t* scratch,
										 OutputSegment* output,
										 int32_t outputCapacity,
										 DeviceSummary* summary)
{
	if (blockIdx.x != 0 || threadIdx.x != 0) return;
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
		bool canBeExtended = edgeAlignment.edgeLen - edgeAlignment.edgeEnd <
							 params.maximumJump;

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
			initChain(chains[chainCount], maxChain, index, parent.firstIndex,
					  parent.length + 1, maxScore);
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
			int32_t overlapRate =
				min(last.readEnd, existingLast.readEnd) -
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

	if (preDivergenceAccepted != divergenceCount)
	{
		summary->errorCode = 1;
		return;
	}

	int32_t outputRecordCount = 0;
	int32_t outputChainId = 0;
	for (int32_t chainIndex = 0; chainIndex < preDivergenceAccepted; ++chainIndex)
	{
		if (!divergenceAccepted[chainIndex]) continue;
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

std::vector<OutputSegment> cudaSegmentsToVector(const std::vector<OutputSegment>& raw,
												size_t count)
{
	if (count > raw.size())
	{
		throw std::runtime_error("CUDA output count exceeds copied segment buffer");
	}
	return std::vector<OutputSegment>(raw.begin(), raw.begin() + static_cast<long>(count));
}

void writeReadAlignment(const std::string& path,
						const std::vector<EdgeOverlap>& overlaps,
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
		output << segment.chainId << "\t"
			   << segment.segmentId << "\t"
			   << item.readId << "\t"
			   << item.readBegin << "\t"
			   << item.readEnd << "\t"
			   << item.readLen << "\t"
			   << item.edgeId << "\t"
			   << item.edgeSeqId << "\t"
			   << item.edgeBegin << "\t"
			   << item.edgeEnd << "\t"
			   << item.edgeLen << "\t"
			   << item.score << "\t";
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

RunSummary runCpu(const LoadedFixture& fixture, std::vector<OutputSegment>& segments)
{
	RunSummary summary;
	summary.backend = "cpu";
	summary.inputRecords = fixture.overlaps.size();
	auto start = Clock::now();
	std::vector<CpuChain> chains =
		cpuChainReadAlignments(fixture.overlaps, fixture.manifest.params);
	segments = buildSegmentsFromCpuChains(chains, fixture.divergenceAccepted);
	auto end = Clock::now();
	summary.cpuChainMs = elapsedMs(start, end);
	summary.candidateChains = chains.size();
	summary.preDivergenceAcceptedChains = chains.size();
	summary.acceptedChains = 0;
	for (uint8_t accepted : fixture.divergenceAccepted)
	{
		if (accepted) ++summary.acceptedChains;
	}
	summary.outputRecords = segments.size();
	summary.totalBeforeJsonMs = summary.cpuChainMs;
	return summary;
}

size_t cudaRequiredBytes(size_t overlapCount, size_t outputCapacity)
{
	return overlapCount * sizeof(EdgeOverlap) +
		   overlapCount * sizeof(uint8_t) +
		   overlapCount * sizeof(ChainRecord) +
		   overlapCount * sizeof(int32_t) * 5 +
		   outputCapacity * sizeof(OutputSegment) +
		   sizeof(DeviceSummary);
}

RunSummary runCuda(const Options& options, const LoadedFixture& fixture,
				   std::vector<OutputSegment>& segments)
{
	RunSummary summary;
	summary.backend = "cuda";
	summary.device = options.device;
	summary.inputRecords = fixture.overlaps.size();
	size_t overlapCount = fixture.overlaps.size();
	size_t outputCapacity = checkedOutputCapacity(overlapCount);
	summary.requiredBytes = cudaRequiredBytes(overlapCount, outputCapacity);
	if (options.hasMemoryBudget &&
		summary.requiredBytes > static_cast<size_t>(options.memoryBudgetBytes))
	{
		throw std::runtime_error("CUDA memory budget exceeded for read-alignment replay");
	}

	auto setupStart = Clock::now();
	cuflye::cuda_raii::checkCuda(cudaSetDevice(options.device), "set CUDA device");
	cudaDeviceProp props{};
	cuflye::cuda_raii::checkCuda(
		cudaGetDeviceProperties(&props, options.device), "get CUDA device properties");
	summary.deviceName = props.name;
	cuflye::cuda_raii::checkCuda(cudaMemGetInfo(&summary.freeBytes, &summary.totalBytes),
								 "query CUDA memory");
	auto setupEnd = Clock::now();
	summary.setupMs = elapsedMs(setupStart, setupEnd);

	auto allocStart = Clock::now();
	cuflye::cuda_raii::DeviceBuffer<EdgeOverlap> dOverlaps(
		overlapCount * sizeof(EdgeOverlap), "read alignment edge overlaps");
	cuflye::cuda_raii::DeviceBuffer<uint8_t> dDivergence(
		fixture.divergenceAccepted.size() * sizeof(uint8_t), "chain divergence flags");
	cuflye::cuda_raii::DeviceBuffer<ChainRecord> dChains(
		overlapCount * sizeof(ChainRecord), "read alignment chains");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dActive(
		overlapCount * sizeof(int32_t), "active chain ids");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dFrozen(
		overlapCount * sizeof(int32_t), "frozen chain ids");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dOrdered(
		overlapCount * sizeof(int32_t), "ordered chain ids");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dAccepted(
		overlapCount * sizeof(int32_t), "accepted chain ids");
	cuflye::cuda_raii::DeviceBuffer<int32_t> dScratch(
		overlapCount * sizeof(int32_t), "chain reconstruction scratch");
	cuflye::cuda_raii::DeviceBuffer<OutputSegment> dOutput(
		outputCapacity * sizeof(OutputSegment), "read alignment output segments");
	cuflye::cuda_raii::DeviceBuffer<DeviceSummary> dSummary(
		sizeof(DeviceSummary), "read alignment summary");
	auto allocEnd = Clock::now();
	summary.deviceAllocationMs = elapsedMs(allocStart, allocEnd);

	auto h2dStart = Clock::now();
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(dOverlaps.get(), fixture.overlaps.data(),
				   overlapCount * sizeof(EdgeOverlap), cudaMemcpyHostToDevice),
		"copy read alignment overlaps to device");
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(dDivergence.get(), fixture.divergenceAccepted.data(),
				   fixture.divergenceAccepted.size() * sizeof(uint8_t),
				   cudaMemcpyHostToDevice),
		"copy chain divergence flags to device");
	auto h2dEnd = Clock::now();
	summary.hostToDeviceMs = elapsedMs(h2dStart, h2dEnd);

	auto kernelStart = Clock::now();
	readAlignmentChainKernel<<<1, 1>>>(
		dOverlaps.get(),
		static_cast<int32_t>(overlapCount),
		dDivergence.get(),
		static_cast<int32_t>(fixture.divergenceAccepted.size()),
		fixture.manifest.params,
		dChains.get(),
		dActive.get(),
		dFrozen.get(),
		dOrdered.get(),
		dAccepted.get(),
		dScratch.get(),
		dOutput.get(),
		static_cast<int32_t>(outputCapacity),
		dSummary.get());
	cuflye::cuda_raii::checkCuda(cudaGetLastError(), "launch read alignment chain kernel");
	cuflye::cuda_raii::checkCuda(cudaDeviceSynchronize(),
								 "synchronize read alignment chain kernel");
	auto kernelEnd = Clock::now();
	summary.kernelMs = elapsedMs(kernelStart, kernelEnd);

	DeviceSummary deviceSummary{};
	std::vector<OutputSegment> rawSegments(outputCapacity);
	auto d2hStart = Clock::now();
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(&deviceSummary, dSummary.get(), sizeof(DeviceSummary),
				   cudaMemcpyDeviceToHost),
		"copy read alignment summary to host");
	if (deviceSummary.outputRecords > 0)
	{
		cuflye::cuda_raii::checkCuda(
			cudaMemcpy(rawSegments.data(), dOutput.get(),
					   static_cast<size_t>(deviceSummary.outputRecords) *
					   sizeof(OutputSegment),
					   cudaMemcpyDeviceToHost),
			"copy read alignment output to host");
	}
	auto d2hEnd = Clock::now();
	summary.deviceToHostMs = elapsedMs(d2hStart, d2hEnd);

	auto finalizeStart = Clock::now();
	if (!deviceSummary.valid)
	{
		throw std::runtime_error("read alignment CUDA replay kernel failed with code " +
								 std::to_string(deviceSummary.errorCode));
	}
	segments = cudaSegmentsToVector(rawSegments,
									static_cast<size_t>(deviceSummary.outputRecords));
	auto finalizeEnd = Clock::now();
	summary.finalizeMs = elapsedMs(finalizeStart, finalizeEnd);
	summary.candidateChains = static_cast<size_t>(deviceSummary.candidateChains);
	summary.preDivergenceAcceptedChains =
		static_cast<size_t>(deviceSummary.preDivergenceAcceptedChains);
	summary.acceptedChains = static_cast<size_t>(deviceSummary.acceptedChains);
	summary.outputRecords = segments.size();
	summary.totalBeforeJsonMs = summary.setupMs + summary.deviceAllocationMs +
								summary.hostToDeviceMs + summary.kernelMs +
								summary.deviceToHostMs + summary.finalizeMs;
	return summary;
}

void attachBenchmarkStats(RunSummary& summary,
						  const std::vector<RunSummary>& timedRuns,
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
		summary.benchmarkMinTotalMs =
			std::min(summary.benchmarkMinTotalMs, run.totalBeforeJsonMs);
		summary.benchmarkMaxTotalMs =
			std::max(summary.benchmarkMaxTotalMs, run.totalBeforeJsonMs);
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
			(void)runCpu(fixture, scratch);
		}
	}

	std::vector<RunSummary> timedRuns;
	for (uint32_t index = 0; index < options.benchmarkRuns; ++index)
	{
		RunSummary summary = options.backend == "cuda" ?
			runCuda(options, fixture, segments) : runCpu(fixture, segments);
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
		   << "  \"fixture_dir\": \"" << jsonEscape(options.fixtureDir) << "\",\n"
		   << "  \"output_tsv\": \"" << jsonEscape(options.outputTsv) << "\",\n"
		   << "  \"query_id\": " << manifest.queryId << ",\n"
		   << "  \"input_records\": " << summary.inputRecords << ",\n"
		   << "  \"candidate_chains\": " << summary.candidateChains << ",\n"
		   << "  \"pre_divergence_accepted_chains\": "
		   << summary.preDivergenceAcceptedChains << ",\n"
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
		   << "    \"reads_base_alignment\": "
		   << (manifest.readsBaseAlignment ? "true" : "false") << ",\n"
		   << "    \"uses_fixture_divergence_acceptance\": true,\n"
		   << "    \"max_replay_records\": " << MAX_REPLAY_RECORDS << "\n"
		   << "  }\n"
		   << "}\n";
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
		if (arg == "--fixture-dir") options.fixtureDir = nextValue();
		else if (arg == "--output-tsv") options.outputTsv = nextValue();
		else if (arg == "--json-output") options.jsonOutput = nextValue();
		else if (arg == "--backend") options.backend = nextValue();
		else if (arg == "--device") options.device = std::stoi(nextValue());
		else if (arg == "--warmup-runs")
		{
			options.warmupRuns = static_cast<uint32_t>(std::stoul(nextValue()));
		}
		else if (arg == "--benchmark-runs")
		{
			options.benchmarkRuns = static_cast<uint32_t>(std::stoul(nextValue()));
		}
		else if (arg == "--memory-budget-bytes")
		{
			options.hasMemoryBudget = true;
			options.memoryBudgetBytes = std::stoull(nextValue());
		}
		else if (arg == "-h" || arg == "--help")
		{
			std::cout
				<< "Usage: cuflye-cuda-read-alignment-chain-replay "
				<< "--fixture-dir DIR --output-tsv PATH --json-output PATH "
				<< "[--backend cpu|cuda] [--device ID] "
				<< "[--warmup-runs N] [--benchmark-runs N] "
				<< "[--memory-budget-bytes BYTES]\n";
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
}
}

int main(int argc, char** argv)
{
	try
	{
		Options options;
		parseArgs(argc, argv, options);
		LoadedFixture fixture = loadFixture(options.fixtureDir);
		std::vector<OutputSegment> segments;
		RunSummary summary = runBenchmark(options, fixture, segments);

		auto writeStart = Clock::now();
		writeReadAlignment(options.outputTsv, fixture.overlaps, segments);
		auto writeEnd = Clock::now();
		summary.writeMs = elapsedMs(writeStart, writeEnd);
		writeJsonSummary(options.jsonOutput, options, fixture.manifest, summary);

		std::cout << "cuFlye read-alignment chain replay: ok\n"
				  << "  backend: " << summary.backend << "\n"
				  << "  input records: " << summary.inputRecords << "\n"
				  << "  output records: " << summary.outputRecords << "\n"
				  << "  mean total before JSON: "
				  << summary.benchmarkMeanTotalMs << " ms\n";
		return 0;
	}
	catch (const std::exception& exc)
	{
		std::cerr << "error: " << exc.what() << "\n";
		return 1;
	}
}
