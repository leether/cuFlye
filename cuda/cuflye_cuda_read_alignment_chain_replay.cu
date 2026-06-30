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
	std::string batchFixturesFile;
	std::string batchOutputDir;
	std::string batchJsonOutput;
	std::string backend = "cuda";
	int device = 0;
	uint32_t warmupRuns = 0;
	uint32_t benchmarkRuns = 1;
	uint32_t replicateFixture = 1;
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
	size_t batchSize = 1;
	size_t inputRecords = 0;
	size_t totalInputRecords = 0;
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

struct BatchFixtureOutput
{
	std::string fixtureDir;
	std::string outputTsv;
	int64_t queryId = 0;
	size_t inputRecords = 0;
	size_t outputRecords = 0;
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

std::vector<LoadedFixture> loadBatchFixtures(const std::string& path)
{
	std::vector<std::string> fixtureDirs = loadFixtureList(path);
	std::vector<LoadedFixture> fixtures;
	fixtures.reserve(fixtureDirs.size());
	for (const std::string& fixtureDir : fixtureDirs)
	{
		fixtures.push_back(loadFixture(fixtureDir));
	}
	if (fixtures.empty())
	{
		throw std::runtime_error("batch fixture list is empty after loading");
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
	divergenceAccepted += static_cast<size_t>(batchId) * static_cast<size_t>(divergenceCount);
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

RunSummary runCpu(const Options& options, const LoadedFixture& fixture,
                  std::vector<OutputSegment>& segments)
{
	RunSummary summary;
	summary.backend = "cpu";
	summary.batchSize = options.replicateFixture;
	summary.inputRecords = fixture.overlaps.size();
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
		    buildSegmentsFromCpuChains(chains, fixture.divergenceAccepted);
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
	summary.acceptedChains = 0;
	for (uint8_t accepted : fixture.divergenceAccepted)
	{
		if (accepted) ++summary.acceptedChains;
	}
	summary.outputRecords = segments.size();
	summary.totalBeforeJsonMs = summary.cpuChainMs;
	return summary;
}

RunSummary runCpuBatch(const Options& options, const std::vector<LoadedFixture>& fixtures,
                       std::vector<std::vector<OutputSegment>>& segmentsByFixture)
{
	(void)options;
	if (fixtures.empty())
	{
		throw std::runtime_error("batch fixture set is empty");
	}

	RunSummary summary;
	summary.backend = "cpu";
	summary.batchSize = fixtures.size();
	summary.inputRecords = fixtures.front().overlaps.size();
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
		    buildSegmentsFromCpuChains(chains, fixture.divergenceAccepted);
		summary.candidateChains += chains.size();
		summary.preDivergenceAcceptedChains += chains.size();
		for (uint8_t accepted : fixture.divergenceAccepted)
		{
			if (accepted) ++summary.acceptedChains;
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
	summary.device = options.device;
	summary.batchSize = options.replicateFixture;
	summary.inputRecords = fixture.overlaps.size();
	summary.totalInputRecords = checkedMul(fixture.overlaps.size(), options.replicateFixture,
	                                       "CUDA replicated total input records");
	size_t overlapCount = fixture.overlaps.size();
	size_t outputCapacity = checkedOutputCapacity(overlapCount);
	size_t batchSize = options.replicateFixture;
	size_t overlapItems = checkedMul(overlapCount, batchSize, "CUDA replicated overlap items");
	size_t divergenceItems = checkedMul(fixture.divergenceAccepted.size(), batchSize,
	                                    "CUDA replicated divergence items");
	size_t outputItems = checkedMul(outputCapacity, batchSize, "CUDA replicated output items");
	summary.requiredBytes = cudaRequiredBytes(overlapCount, fixture.divergenceAccepted.size(),
	                                          outputCapacity, batchSize);
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
		packedDivergence.insert(packedDivergence.end(), fixture.divergenceAccepted.begin(),
		                        fixture.divergenceAccepted.end());
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
	cuflye::cuda_raii::checkCuda(cudaMemcpy(dDivergence.get(), packedDivergence.data(),
	                                        checkedMul(packedDivergence.size(), sizeof(uint8_t),
	                                                   "copy read alignment divergence bytes"),
	                                        cudaMemcpyHostToDevice),
	                             "copy chain divergence flags to device");
	auto h2dEnd = Clock::now();
	summary.hostToDeviceMs = elapsedMs(h2dStart, h2dEnd);

	auto kernelStart = Clock::now();
	readAlignmentChainKernel<<<static_cast<unsigned int>(batchSize), 1>>>(
	    dOverlaps.get(), static_cast<int32_t>(overlapCount), dDivergence.get(),
	    static_cast<int32_t>(fixture.divergenceAccepted.size()), fixture.manifest.params,
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
	summary.device = options.device;
	summary.batchSize = fixtures.size();
	summary.inputRecords = fixtures.front().overlaps.size();
	summary.totalInputRecords =
	    checkedMul(summary.inputRecords, fixtures.size(), "CUDA batch total input records");
	size_t overlapCount = fixtures.front().overlaps.size();
	size_t divergenceCount = fixtures.front().divergenceAccepted.size();
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
		packedDivergence.insert(packedDivergence.end(), fixture.divergenceAccepted.begin(),
		                        fixture.divergenceAccepted.end());
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
	cuflye::cuda_raii::checkCuda(
	    cudaMemcpy(dDivergence.get(), packedDivergence.data(),
	               checkedMul(packedDivergence.size(), sizeof(uint8_t),
	                          "copy read alignment batch divergence bytes"),
	               cudaMemcpyHostToDevice),
	    "copy read alignment batch divergence to device");
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
	std::vector<std::vector<OutputSegment>> scratch;
	for (uint32_t index = 0; index < options.warmupRuns; ++index)
	{
		if (options.backend == "cuda")
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
		RunSummary summary = options.backend == "cuda"
		                         ? runCudaBatch(options, fixtures, segmentsByFixture)
		                         : runCpuBatch(options, fixtures, segmentsByFixture);
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
	       << "    \"uses_fixture_divergence_acceptance\": true,\n"
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
		output.outputRecords = segmentsByFixture[index].size();
		outputs.push_back(output);
	}
	return outputs;
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
	output << std::fixed << std::setprecision(6);
	output << "{\n"
	       << "  \"schema\": \"cuflye-cuda-read-alignment-chain-replay-batch-v0\",\n"
	       << "  \"status\": \"ok\",\n"
	       << "  \"backend\": \"" << jsonEscape(summary.backend) << "\",\n"
	       << "  \"batch_fixtures_file\": \"" << jsonEscape(options.batchFixturesFile) << "\",\n"
	       << "  \"batch_output_dir\": \"" << jsonEscape(options.batchOutputDir) << "\",\n"
	       << "  \"fixture_count\": " << fixtureOutputs.size() << ",\n"
	       << "  \"batch_size\": " << summary.batchSize << ",\n"
	       << "  \"input_records_per_fixture\": " << summary.inputRecords << ",\n"
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
	       << "    \"same_alignment_input_records_required\": true,\n"
	       << "    \"same_chain_divergence_count_required\": true,\n"
	       << "    \"same_replay_parameters_required\": true,\n"
	       << "    \"uses_fixture_divergence_acceptance\": true,\n"
	       << "    \"representative_output_only\": false,\n"
	       << "    \"max_replay_records\": " << MAX_REPLAY_RECORDS << "\n"
	       << "  },\n"
	       << "  \"fixtures\": [\n";
	for (size_t index = 0; index < fixtureOutputs.size(); ++index)
	{
		const BatchFixtureOutput& fixture = fixtureOutputs[index];
		output << "    {\n"
		       << "      \"fixture_dir\": \"" << jsonEscape(fixture.fixtureDir) << "\",\n"
		       << "      \"output_tsv\": \"" << jsonEscape(fixture.outputTsv) << "\",\n"
		       << "      \"query_id\": " << fixture.queryId << ",\n"
		       << "      \"input_records\": " << fixture.inputRecords << ",\n"
		       << "      \"output_records\": " << fixture.outputRecords << "\n"
		       << "    }";
		if (index + 1 != fixtureOutputs.size()) output << ",";
		output << "\n";
	}
	output << "  ]\n"
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
		else if (arg == "-h" || arg == "--help")
		{
			std::cout << "Usage: cuflye-cuda-read-alignment-chain-replay "
			          << "--fixture-dir DIR --output-tsv PATH --json-output PATH "
			          << "[--backend cpu|cuda] [--device ID] "
			          << "[--warmup-runs N] [--benchmark-runs N] "
			          << "[--replicate-fixture N] "
			          << "[--memory-budget-bytes BYTES]\n"
			          << "Batch mode: cuflye-cuda-read-alignment-chain-replay "
			          << "--batch-fixtures-file FILE --batch-output-dir DIR "
			          << "--batch-json-output PATH [--backend cpu|cuda] "
			          << "[--device ID] [--warmup-runs N] [--benchmark-runs N] "
			          << "[--memory-budget-bytes BYTES]\n";
			std::exit(0);
		}
		else
		{
			throw std::runtime_error("unknown option: " + arg);
		}
	}

	bool batchMode = !options.batchFixturesFile.empty() || !options.batchOutputDir.empty() ||
	                 !options.batchJsonOutput.empty();
	if (batchMode)
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
	}
	else
	{
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
}
} // namespace

int main(int argc, char** argv)
{
	try
	{
		Options options;
		parseArgs(argc, argv, options);
		if (!options.batchFixturesFile.empty())
		{
			std::vector<LoadedFixture> fixtures = loadBatchFixtures(options.batchFixturesFile);
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
			          << "  fixture count: " << outputs.size() << "\n"
			          << "  input records per fixture: " << summary.inputRecords << "\n"
			          << "  total input records: " << summary.totalInputRecords << "\n"
			          << "  output records: " << summary.outputRecords << "\n"
			          << "  mean total before JSON: " << summary.benchmarkMeanTotalMs << " ms\n";
			return 0;
		}

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
