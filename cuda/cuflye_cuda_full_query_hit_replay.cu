// SPDX-License-Identifier: BSD-3-Clause

#include <cuda_runtime_api.h>

#include "cuflye_cuda_raii.hpp"

#include <algorithm>
#include <cerrno>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <limits>
#include <map>
#include <memory>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>
#include <vector>

namespace
{
using Clock = std::chrono::steady_clock;

const int32_t kMaxSupportedGroupMatches = 4096;
const int32_t kParallelScoreThreads = 128;
const float kLargeGapPenalty = 2.0f;
const float kSmallGapPenalty = 0.5f;
const int32_t kGapJumpThreshold = 100;
const int32_t kMaxJumpGap = 500;
const float kMinKmerSurvivalRate = 0.01f;
const float kMaxDivergence = 1.0f;

struct MatchRecord
{
	int32_t curPos;
	int32_t extPos;
	int64_t extId;
	int32_t sourceOrder;
};

struct GroupRecord
{
	int64_t queryId;
	int32_t queryOrdinal;
	int32_t queryLen;
	int64_t extId;
	int32_t extLen;
	int32_t matchOffset;
	int32_t matchCount;
	int32_t outputOffset;
	int32_t kmerSize;
	int32_t maxJump;
	int32_t minOverlap;
};

struct OverlapRecord
{
	int64_t queryId;
	int32_t queryOrdinal;
	int32_t curBegin;
	int32_t curEnd;
	int32_t curLen;
	int64_t extId;
	int32_t extBegin;
	int32_t extEnd;
	int32_t extLen;
	int32_t score;
	float seqDivergence;
	int32_t chainLength;
};

struct QuerySummary
{
	int64_t queryId = 0;
	int32_t queryLen = 0;
	int32_t chainInputCount = 0;
	int32_t outputRecords = 0;
};

struct QueryParams
{
	int32_t kmerSize = 0;
	int32_t maxJump = 0;
	int32_t minOverlap = 0;
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
	std::string workerRequestJson;
	std::string workerRequestsJsonl;
	std::string workerSessionDir;
	std::string kernelMode = "serial";
	int device = 0;
	int repeatCount = 1;
	uint32_t workerSessionMaxRequests = 1;
	uint32_t workerSessionPollMs = 2;
	uint32_t workerSessionTimeoutMs = 600000;
	bool hasMemoryBudget = false;
	unsigned long long memoryBudgetBytes = 0;
};

struct RequestTiming
{
	double resetMs = 0.0;
	double kernelMs = 0.0;
	double deviceToHostMs = 0.0;
	double requestTotalMs = 0.0;
	int32_t outputRecords = 0;
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
	size_t sourceMatchRecords = 0;
	size_t extGroups = 0;
	size_t activeGroups = 0;
	size_t outputRecords = 0;
	size_t requiredBytes = 0;
	size_t freeBytes = 0;
	size_t totalBytes = 0;
	int device = 0;
	int parallelThreads = 1;
	int repeatCount = 1;
	std::string deviceName;
	std::string kernelMode;
	std::vector<RequestTiming> requestTimings;
};

struct ReplaySession
{
	bool initialized = false;
	Options options;
	std::vector<QuerySummary> queries;
	std::vector<MatchRecord> flatMatches;
	std::vector<GroupRecord> groups;
	std::vector<int32_t> scoreTable;
	std::vector<int32_t> backtrackTable;
	std::vector<int32_t> orderScratch;
	std::vector<OverlapRecord> proposalRows;
	std::vector<int32_t> proposalCounts;
	std::vector<OverlapRecord> outputRows;
	std::vector<int32_t> outputCounts;
	DeviceStatus zeroStatus{0, 0};
	DeviceStatus lastStatus{0, 0};
	cuflye::cuda_raii::DeviceBuffer<MatchRecord> dMatches;
	cuflye::cuda_raii::DeviceBuffer<GroupRecord> dGroups;
	cuflye::cuda_raii::DeviceBuffer<int32_t> dScore;
	cuflye::cuda_raii::DeviceBuffer<int32_t> dBacktrack;
	cuflye::cuda_raii::DeviceBuffer<int32_t> dOrder;
	cuflye::cuda_raii::DeviceBuffer<OverlapRecord> dProposals;
	cuflye::cuda_raii::DeviceBuffer<int32_t> dProposalCounts;
	cuflye::cuda_raii::DeviceBuffer<OverlapRecord> dOutput;
	cuflye::cuda_raii::DeviceBuffer<int32_t> dOutputCounts;
	cuflye::cuda_raii::DeviceBuffer<DeviceStatus> dStatus;
	double parseMs = 0.0;
	double hostPackMs = 0.0;
	double deviceAllocationMs = 0.0;
	double hostToDeviceMs = 0.0;
	size_t sourceMatchRecords = 0;
	size_t extGroups = 0;
	size_t activeGroups = 0;
	size_t requiredBytes = 0;
	size_t freeBytes = 0;
	size_t totalBytes = 0;
	std::string deviceName;
};

struct WorkerRequest
{
	std::string schema;
	std::string requestId;
	std::string responseJson;
	std::string adapterMode;
	std::string rawOverlapAbi;
	Options options;
	bool hasExpectedOutputRecords = false;
	size_t expectedOutputRecords = 0;
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

uint32_t parsePositiveU32(const std::string& text, const std::string& name)
{
	int64_t value = parseI64(text, name);
	if (value <= 0 || value > std::numeric_limits<uint32_t>::max())
	{
		throw std::runtime_error(name + " must be a positive uint32 integer");
	}
	return static_cast<uint32_t>(value);
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

std::string readFile(const std::string& path)
{
	std::ifstream input(path.c_str());
	if (!input)
	{
		throw std::runtime_error("can't open file: " + path);
	}
	return std::string((std::istreambuf_iterator<char>(input)),
					   std::istreambuf_iterator<char>());
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

void writeTextFile(const std::string& path, const std::string& text)
{
	std::ofstream output(path.c_str());
	if (!output)
	{
		throw std::runtime_error("can't write text file: " + path);
	}
	output << text;
}

void ensureDirectory(const std::string& path)
{
	if (::mkdir(path.c_str(), 0775) == 0) return;
	if (errno == EEXIST) return;
	throw std::runtime_error("can't create directory: " + path + ": " +
							 std::strerror(errno));
}

bool hasSuffix(const std::string& value, const std::string& suffix)
{
	return value.size() >= suffix.size() &&
		   value.compare(value.size() - suffix.size(), suffix.size(), suffix) == 0;
}

std::string baseName(const std::string& path)
{
	size_t slash = path.find_last_of('/');
	if (slash == std::string::npos) return path;
	return path.substr(slash + 1);
}

void renameFile(const std::string& from, const std::string& to)
{
	if (::rename(from.c_str(), to.c_str()) != 0)
	{
		throw std::runtime_error("can't rename " + from + " to " + to +
								 ": " + std::strerror(errno));
	}
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
		default: throw std::runtime_error("unsupported JSON escape sequence");
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
			"nested JSON values are not supported by full query-hit worker v0");
	}
	size_t begin = offset;
	while (offset < text.size() && text[offset] != ',' && text[offset] != '}')
	{
		++offset;
	}
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
	if (offset != text.size())
	{
		throw std::runtime_error("unexpected characters after JSON object");
	}
	return fields;
}

std::string requireJsonField(const std::map<std::string, std::string>& fields,
							 const std::string& key)
{
	auto iter = fields.find(key);
	if (iter == fields.end() || iter->second.empty())
	{
		throw std::runtime_error(
			"full query-hit worker request missing required field: " + key);
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
	if (value[0] == '-') throw std::runtime_error(name + " must be unsigned");
	char* end = nullptr;
	errno = 0;
	unsigned long long parsed = std::strtoull(value.c_str(), &end, 10);
	if (errno != 0 || end == value.c_str() || *end != '\0')
	{
		throw std::runtime_error(name + " must be an unsigned decimal integer");
	}
	return parsed;
}

int32_t parseJsonI32(const std::string& text, const std::string& key)
{
	std::string quotedKey = "\"" + key + "\"";
	size_t keyPos = text.find(quotedKey);
	if (keyPos == std::string::npos)
	{
		throw std::runtime_error("manifest lacks " + quotedKey);
	}
	size_t colon = text.find(':', keyPos + quotedKey.size());
	if (colon == std::string::npos)
	{
		throw std::runtime_error("manifest key lacks colon: " + quotedKey);
	}
	size_t valueStart = text.find_first_of("-0123456789", colon + 1);
	if (valueStart == std::string::npos)
	{
		throw std::runtime_error("manifest key lacks integer: " + quotedKey);
	}
	size_t valueEnd = valueStart;
	while (valueEnd < text.size() &&
		   (text[valueEnd] == '-' ||
			(text[valueEnd] >= '0' && text[valueEnd] <= '9')))
	{
		++valueEnd;
	}
	return parseI32(text.substr(valueStart, valueEnd - valueStart), key);
}

QueryParams loadQueryParams(const std::string& queryDir)
{
	std::string manifest = readFile(joinPath(queryDir, "manifest.json"));
	if (manifest.find(
			"\"schema\": \"cuflye-read-to-graph-minimizer-source-pack-v0\"") ==
		std::string::npos)
	{
		throw std::runtime_error(queryDir + ": unsupported source-pack schema");
	}
	QueryParams params;
	params.kmerSize = parseJsonI32(manifest, "kmer_size");
	params.maxJump = parseJsonI32(manifest, "maximum_jump");
	if (manifest.find("\"small_alignment_threshold\"") != std::string::npos)
	{
		params.minOverlap = parseJsonI32(manifest, "small_alignment_threshold");
	}
	else
	{
		params.minOverlap = parseJsonI32(manifest, "minimum_overlap");
	}
	if (params.kmerSize <= 0 || params.maxJump <= 0 || params.minOverlap <= 0)
	{
		throw std::runtime_error(queryDir + ": invalid replay parameters");
	}
	return params;
}

std::pair<int64_t, int32_t> loadQuery(const std::string& queryDir)
{
	std::string path = joinPath(queryDir, "query.tsv");
	std::ifstream input(path.c_str());
	if (!input)
	{
		throw std::runtime_error("can't open query TSV: " + path);
	}
	requireSchemaLine(input, path, "# schema=cuflye-read-to-graph-source-query-v0");
	requireHeaderLine(input, path, "query_id\tsequence");
	std::string line;
	if (!std::getline(input, line))
	{
		throw std::runtime_error(path + ": missing query row");
	}
	auto fields = splitTab(line);
	if (fields.size() != 2 || fields[1].empty())
	{
		throw std::runtime_error(path + ": query row must have 2 fields");
	}
	return {parseI64(fields[0], "query_id"),
			static_cast<int32_t>(fields[1].size())};
}

std::map<int64_t, int32_t> loadEdgeLengths(const std::string& queryDir)
{
	std::string path = joinPath(queryDir, "edge-sequences.tsv");
	std::ifstream input(path.c_str());
	if (!input)
	{
		throw std::runtime_error("can't open edge sequences TSV: " + path);
	}
	requireSchemaLine(
		input, path, "# schema=cuflye-read-to-graph-source-edge-sequence-v0");
	requireHeaderLine(input, path, "edge_seq_id\tedge_seq_len\tsequence");
	std::map<int64_t, int32_t> edgeLengths;
	std::string line;
	while (std::getline(input, line))
	{
		auto fields = splitTab(line);
		if (fields.size() != 3)
		{
			throw std::runtime_error(path + ": edge sequence row must have 3 fields");
		}
		int64_t edgeId = parseI64(fields[0], "edge_seq_id");
		int32_t edgeLen = parseI32(fields[1], "edge_seq_len");
		if (edgeLen != static_cast<int32_t>(fields[2].size()))
		{
			throw std::runtime_error(path + ": edge sequence length mismatch");
		}
		edgeLengths[edgeId] = edgeLen;
	}
	if (edgeLengths.empty())
	{
		throw std::runtime_error(path + ": edge sequence set is empty");
	}
	return edgeLengths;
}

int32_t loadOracleChainInputCount(const std::string& queryDir)
{
	std::string path = joinPath(queryDir, "raw-overlaps.tsv");
	std::ifstream input(path.c_str());
	if (!input) return 0;
	requireSchemaLine(input, path, "# schema=cuflye-read-to-graph-raw-overlap-v0");
	requireHeaderLine(
		input, path,
		"query_id\tsource_order\traw_overlap_count\tchain_input_count\tread_id\t"
		"read_begin\tread_end\tread_len\tedge_seq_id\tedge_begin\tedge_end\t"
		"edge_len\tedge_id\tscore\tseq_divergence\tpasses_chain_input_filter");
	std::string line;
	if (!std::getline(input, line)) return 0;
	auto fields = splitTab(line);
	if (fields.size() != 16)
	{
		throw std::runtime_error(path + ": raw-overlap row must have 16 fields");
	}
	return parseI32(fields[3], "chain_input_count");
}

int64_t signedToInternalId(int64_t signedId)
{
	if (signedId > 0) return 2 * (signedId - 1);
	return 2 * (-signedId) - 1;
}

std::vector<MatchRecord> loadFullQueryHits(const std::string& queryDir,
										   int64_t queryId)
{
	std::string path = joinPath(queryDir, "full-query-hits.tsv");
	std::ifstream input(path.c_str());
	if (!input)
	{
		throw std::runtime_error("can't open full query-hit TSV: " + path);
	}
	requireSchemaLine(
		input, path, "# schema=cuflye-read-to-graph-source-full-query-hit-v0");
	requireHeaderLine(
		input, path,
		"query_id\tsource_order\tquery_pos\tquery_kmer_repr\t"
		"standard_kmer_repr\tstandard_revcomp\tis_repetitive\tkmer_freq\t"
		"target_edge_seq_id\ttarget_pos");

	std::vector<MatchRecord> matches;
	std::string line;
	while (std::getline(input, line))
	{
		auto fields = splitTab(line);
		if (fields.size() != 10)
		{
			throw std::runtime_error(path + ": full query-hit row must have 10 fields");
		}
		int64_t rowQueryId = parseI64(fields[0], "query_id");
		if (rowQueryId != queryId)
		{
			throw std::runtime_error(path + ": mixed query ids");
		}
		MatchRecord match;
		match.sourceOrder = parseI32(fields[1], "source_order");
		match.curPos = parseI32(fields[2], "query_pos");
		int32_t isRepetitive = parseI32(fields[6], "is_repetitive");
		int32_t kmerFreq = parseI32(fields[7], "kmer_freq");
		match.extId = parseI64(fields[8], "target_edge_seq_id");
		match.extPos = parseI32(fields[9], "target_pos");
		if (isRepetitive || !kmerFreq)
		{
			throw std::runtime_error(path + ": non-replayable full query-hit row");
		}
		if (match.extId == queryId && match.extPos == match.curPos) continue;
		matches.push_back(match);
	}
	if (matches.empty())
	{
		throw std::runtime_error(path + ": full query-hit set is empty");
	}
	std::sort(matches.begin(), matches.end(),
			  [](const MatchRecord& left, const MatchRecord& right)
			  {
				  int64_t leftId = signedToInternalId(left.extId);
				  int64_t rightId = signedToInternalId(right.extId);
				  return leftId != rightId ? leftId < rightId :
											 left.curPos < right.curPos;
			  });
	return matches;
}

std::vector<std::pair<int64_t, std::string>> discoverQueryDirs(
	const std::string& packDir)
{
	DIR* rawDir = opendir(packDir.c_str());
	if (!rawDir)
	{
		throw std::runtime_error("can't open source-pack directory: " + packDir);
	}
	std::vector<std::pair<int64_t, std::string>> dirs;
	while (dirent* entry = readdir(rawDir))
	{
		const char* name = entry->d_name;
		const char* prefix = "query_";
		size_t prefixLen = std::strlen(prefix);
		if (std::strncmp(name, prefix, prefixLen) != 0) continue;
		std::string idText(name + prefixLen);
		if (idText.empty()) continue;
		int64_t queryId = parseI64(idText, "query directory id");
		dirs.push_back({queryId, joinPath(packDir, name)});
	}
	closedir(rawDir);
	std::sort(dirs.begin(), dirs.end());
	if (dirs.empty())
	{
		throw std::runtime_error(packDir + ": no query_* directories found");
	}
	return dirs;
}

bool prefilterGroup(const std::vector<MatchRecord>& group, int32_t extLen,
					int32_t minOverlap)
{
	size_t uniqueMatches = 0;
	int32_t prevPos = 0;
	for (const auto& match : group)
	{
		if (match.curPos != prevPos)
		{
			++uniqueMatches;
			prevPos = match.curPos;
		}
	}
	if (uniqueMatches < kMinKmerSurvivalRate * minOverlap) return false;

	int32_t minCur = group.front().curPos;
	int32_t maxCur = group.back().curPos;
	int32_t minExt = std::numeric_limits<int32_t>::max();
	int32_t maxExt = std::numeric_limits<int32_t>::min();
	for (const auto& match : group)
	{
		minExt = std::min(minExt, match.extPos);
		maxExt = std::max(maxExt, match.extPos);
	}
	(void)extLen;
	return maxCur - minCur >= minOverlap && maxExt - minExt >= minOverlap;
}

size_t checkedBytes(size_t count, size_t itemSize, const std::string& label)
{
	if (itemSize != 0 && count > std::numeric_limits<size_t>::max() / itemSize)
	{
		throw std::runtime_error(label + " byte size overflows size_t");
	}
	return count * itemSize;
}

size_t checkedAdd(size_t left, size_t right, const std::string& label)
{
	if (left > std::numeric_limits<size_t>::max() - right)
	{
		throw std::runtime_error(label + " byte total overflows size_t");
	}
	return left + right;
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
		if (arg == "--source-pack-dir") options.packDir = requireValue(arg);
		else if (arg == "--output-tsv") options.outputTsv = requireValue(arg);
		else if (arg == "--json-output") options.jsonOutput = requireValue(arg);
		else if (arg == "--worker-request-json")
			options.workerRequestJson = requireValue(arg);
		else if (arg == "--worker-requests-jsonl")
			options.workerRequestsJsonl = requireValue(arg);
		else if (arg == "--worker-session-dir")
			options.workerSessionDir = requireValue(arg);
		else if (arg == "--kernel-mode") options.kernelMode = requireValue(arg);
		else if (arg == "--device") options.device = parseI32(requireValue(arg), arg);
		else if (arg == "--repeat-count")
			options.repeatCount = parseI32(requireValue(arg), arg);
		else if (arg == "--worker-session-max-requests")
			options.workerSessionMaxRequests = parsePositiveU32(requireValue(arg), arg);
		else if (arg == "--worker-session-poll-ms")
			options.workerSessionPollMs = parsePositiveU32(requireValue(arg), arg);
		else if (arg == "--worker-session-timeout-ms")
			options.workerSessionTimeoutMs = parsePositiveU32(requireValue(arg), arg);
		else if (arg == "--memory-budget-bytes")
		{
			options.hasMemoryBudget = true;
			options.memoryBudgetBytes =
				static_cast<unsigned long long>(parseI64(requireValue(arg), arg));
		}
		else if (arg == "-h" || arg == "--help")
		{
			std::cout << "Usage: cuflye-cuda-full-query-hit-replay "
					  << "--source-pack-dir DIR --output-tsv PATH "
					  << "[--json-output PATH] "
					  << "or --worker-request-json PATH "
					  << "or --worker-requests-jsonl PATH "
					  << "or --worker-session-dir DIR "
					  << "[--kernel-mode serial|parallel-score] [--device ID] "
					  << "[--repeat-count N] "
					  << "[--worker-session-max-requests N] "
					  << "[--worker-session-poll-ms N] "
					  << "[--worker-session-timeout-ms N] "
					  << "[--memory-budget-bytes N]\n";
			std::exit(0);
		}
		else
		{
			throw std::runtime_error("unknown option: " + arg);
		}
	}
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
		if (!options.packDir.empty() || !options.outputTsv.empty() ||
			!options.jsonOutput.empty())
		{
			throw std::runtime_error(
				"worker mode cannot be combined with direct replay mode");
		}
	}
	else
	{
		if (options.packDir.empty())
		{
			throw std::runtime_error("--source-pack-dir is required");
		}
		if (options.outputTsv.empty())
		{
			throw std::runtime_error("--output-tsv is required");
		}
	}
	if (options.kernelMode != "serial" && options.kernelMode != "parallel-score")
	{
		throw std::runtime_error("--kernel-mode must be serial or parallel-score");
	}
	if (options.repeatCount <= 0) throw std::runtime_error("--repeat-count must be > 0");
	return options;
}

__device__ int32_t deviceAbs(int32_t value)
{
	return value < 0 ? -value : value;
}

__device__ int64_t rcSignedId(int64_t signedId)
{
	return -signedId;
}

__device__ bool containedBy(const OverlapRecord& row,
							const OverlapRecord& other)
{
	if (row.queryId != other.queryId || row.extId != other.extId) return false;
	return other.curBegin <= row.curBegin && row.curEnd <= other.curEnd &&
		   other.extBegin <= row.extBegin && row.extEnd <= other.extEnd;
}

__device__ bool overlapTest(const OverlapRecord& row, int32_t minOverlap)
{
	int32_t curRange = row.curEnd - row.curBegin;
	int32_t extRange = row.extEnd - row.extBegin;
	if (curRange < minOverlap || extRange < minOverlap) return false;
	int32_t lengthDiff = deviceAbs(curRange - extRange);
	if (2 * lengthDiff > min(curRange, extRange)) return false;
	if (row.queryId == row.extId)
	{
		int32_t intersect =
			min(row.curEnd, row.extEnd) - max(row.curBegin, row.extBegin);
		if (2 * intersect > curRange) return false;
	}
	if (row.queryId == rcSignedId(row.extId))
	{
		int32_t intersect =
			min(row.curEnd, row.extLen - row.extBegin) -
			max(row.curBegin, row.extLen - row.extEnd);
		if (2 * intersect > curRange) return false;
	}
	return true;
}

__device__ void sortIndicesByScore(int32_t* values, int32_t count,
								   const int32_t* scores)
{
	for (int32_t i = 1; i < count; ++i)
	{
		int32_t value = values[i];
		int32_t j = i - 1;
		while (j >= 0 && scores[value] > scores[values[j]])
		{
			values[j + 1] = values[j];
			--j;
		}
		values[j + 1] = value;
	}
}

__device__ void sortOverlapsByScore(OverlapRecord* values, int32_t count)
{
	for (int32_t i = 1; i < count; ++i)
	{
		OverlapRecord value = values[i];
		int32_t j = i - 1;
		while (j >= 0 && value.score > values[j].score)
		{
			values[j + 1] = values[j];
			--j;
		}
		values[j + 1] = value;
	}
}

__global__ void replayFullQueryHitGroupsKernel(
	const MatchRecord* matches,
	const GroupRecord* groups,
	int32_t groupCount,
	int32_t* scoreTable,
	int32_t* backtrackTable,
	int32_t* orderScratch,
	OverlapRecord* proposalRows,
	int32_t* proposalCounts,
	OverlapRecord* outputRows,
	int32_t* outputCounts,
	DeviceStatus* status)
{
	int32_t groupIdx = blockIdx.x;
	if (groupIdx >= groupCount || threadIdx.x != 0) return;
	GroupRecord group = groups[groupIdx];
	if (group.matchCount <= 0 ||
		group.matchCount > kMaxSupportedGroupMatches)
	{
		status->errorCode = 1;
		return;
	}

	int32_t base = group.matchOffset;
	scoreTable[base] = 0;
	backtrackTable[base] = -1;
	for (int32_t i = 1; i < group.matchCount; ++i)
	{
		int32_t maxScore = 0;
		int32_t maxId = 0;
		int32_t curNext = matches[base + i].curPos;
		int32_t extNext = matches[base + i].extPos;
		for (int32_t j = i - 1; j >= 0; --j)
		{
			int32_t curPrev = matches[base + j].curPos;
			int32_t extPrev = matches[base + j].extPos;
			int32_t curDelta = curNext - curPrev;
			int32_t extDelta = extNext - extPrev;
			int32_t jumpDiv = deviceAbs(curDelta - extDelta);
			if (0 < curDelta && curDelta < group.maxJump &&
				0 < extDelta && extDelta < group.maxJump &&
				jumpDiv <= kMaxJumpGap)
			{
				int32_t matchScore = min(min(curDelta, extDelta), group.kmerSize);
				float penalty = jumpDiv > kGapJumpThreshold ? kLargeGapPenalty :
															 kSmallGapPenalty;
				int32_t gapCost = static_cast<int32_t>(penalty * jumpDiv);
				int32_t nextScore = scoreTable[base + j] + matchScore - gapCost;
				if (nextScore > maxScore)
				{
					maxScore = nextScore;
					maxId = j;
					if (jumpDiv == 0 && curDelta < group.kmerSize) break;
				}
			}
			if (group.extLen > group.queryLen && extDelta > group.maxJump) break;
			if (group.extLen <= group.queryLen && curDelta > group.maxJump) break;
		}
		scoreTable[base + i] = max(maxScore, group.kmerSize);
		backtrackTable[base + i] = maxScore > group.kmerSize ? maxId : -1;
	}

	for (int32_t i = 0; i < group.matchCount; ++i) orderScratch[base + i] = i;
	sortIndicesByScore(orderScratch + base, group.matchCount, scoreTable + base);

	int32_t proposalCount = 0;
	for (int32_t orderIdx = 0; orderIdx < group.matchCount; ++orderIdx)
	{
		int32_t chainStart = orderScratch[base + orderIdx];
		if (backtrackTable[base + chainStart] == -1) continue;
		int32_t lastMatch = chainStart;
		int32_t firstMatch = 0;
		int32_t chainLength = 0;
		int32_t pos = chainStart;
		while (pos != -1)
		{
			firstMatch = pos;
			++chainLength;
			int32_t newPos = backtrackTable[base + pos];
			backtrackTable[base + pos] = -1;
			pos = newPos;
		}

		OverlapRecord row;
		row.queryId = group.queryId;
		row.queryOrdinal = group.queryOrdinal;
		row.curBegin = matches[base + firstMatch].curPos;
		row.extBegin = matches[base + firstMatch].extPos;
		row.curLen = group.queryLen;
		row.extId = group.extId;
		row.extLen = group.extLen;
		row.curEnd = matches[base + lastMatch].curPos + group.kmerSize - 1;
		row.extEnd = matches[base + lastMatch].extPos + group.kmerSize - 1;
		row.score = scoreTable[base + lastMatch] -
					scoreTable[base + firstMatch] + group.kmerSize - 1;
		row.seqDivergence = 0.0f;
		row.chainLength = chainLength;
		if (!overlapTest(row, group.minOverlap)) continue;
		int32_t curRange = row.curEnd - row.curBegin;
		int32_t extRange = row.extEnd - row.extBegin;
		int32_t normLen = max(curRange, extRange);
		if (normLen <= 0) continue;
		float matchRate = static_cast<float>(chainLength) /
						  static_cast<float>(normLen);
		if (matchRate > 1.0f) matchRate = 1.0f;
		if (matchRate <= 0.0f) continue;
		row.seqDivergence = logf(1.0f / matchRate) /
							static_cast<float>(group.kmerSize);
		proposalRows[base + proposalCount] = row;
		++proposalCount;
	}
	proposalCounts[groupIdx] = proposalCount;
	sortOverlapsByScore(proposalRows + base, proposalCount);

	int32_t outputCount = 0;
	for (int32_t i = 0; i < proposalCount; ++i)
	{
		OverlapRecord row = proposalRows[base + i];
		bool isContained = false;
		for (int32_t j = 0; j < outputCount; ++j)
		{
			OverlapRecord primary = outputRows[group.outputOffset + j];
			if (containedBy(row, primary) && primary.score > row.score)
			{
				isContained = true;
				break;
			}
		}
		if (!isContained && row.seqDivergence < kMaxDivergence)
		{
			outputRows[group.outputOffset + outputCount] = row;
			++outputCount;
		}
	}
	outputCounts[groupIdx] = outputCount;
	atomicAdd(&status->outputRecords, outputCount);
}

__device__ bool betterScoreCandidate(int32_t score, int32_t id,
									 int32_t bestScore, int32_t bestId)
{
	return score > bestScore || (score == bestScore && id > bestId);
}

__global__ void replayFullQueryHitGroupsParallelScoreKernel(
	const MatchRecord* matches,
	const GroupRecord* groups,
	int32_t groupCount,
	int32_t* scoreTable,
	int32_t* backtrackTable,
	int32_t* orderScratch,
	OverlapRecord* proposalRows,
	int32_t* proposalCounts,
	OverlapRecord* outputRows,
	int32_t* outputCounts,
	DeviceStatus* status)
{
	__shared__ int32_t sharedScores[kParallelScoreThreads];
	__shared__ int32_t sharedIds[kParallelScoreThreads];

	int32_t groupIdx = blockIdx.x;
	if (groupIdx >= groupCount) return;
	GroupRecord group = groups[groupIdx];
	if (group.matchCount <= 0 ||
		group.matchCount > kMaxSupportedGroupMatches ||
		blockDim.x != kParallelScoreThreads)
	{
		if (threadIdx.x == 0) status->errorCode = 1;
		return;
	}

	int32_t base = group.matchOffset;
	if (threadIdx.x == 0)
	{
		scoreTable[base] = 0;
		backtrackTable[base] = -1;
	}
	__syncthreads();

	for (int32_t i = 1; i < group.matchCount; ++i)
	{
		int32_t localBestScore = 0;
		int32_t localBestId = 0;
		int32_t curNext = matches[base + i].curPos;
		int32_t extNext = matches[base + i].extPos;
		for (int32_t j = i - 1 - static_cast<int32_t>(threadIdx.x);
			 j >= 0; j -= blockDim.x)
		{
			int32_t curPrev = matches[base + j].curPos;
			int32_t extPrev = matches[base + j].extPos;
			int32_t curDelta = curNext - curPrev;
			int32_t extDelta = extNext - extPrev;
			int32_t jumpDiv = deviceAbs(curDelta - extDelta);
			if (0 < curDelta && curDelta < group.maxJump &&
				0 < extDelta && extDelta < group.maxJump &&
				jumpDiv <= kMaxJumpGap)
			{
				int32_t matchScore = min(min(curDelta, extDelta), group.kmerSize);
				float penalty = jumpDiv > kGapJumpThreshold ? kLargeGapPenalty :
															 kSmallGapPenalty;
				int32_t gapCost = static_cast<int32_t>(penalty * jumpDiv);
				int32_t nextScore = scoreTable[base + j] + matchScore - gapCost;
				if (betterScoreCandidate(nextScore, j,
										 localBestScore, localBestId))
				{
					localBestScore = nextScore;
					localBestId = j;
				}
			}
		}

		sharedScores[threadIdx.x] = localBestScore;
		sharedIds[threadIdx.x] = localBestId;
		__syncthreads();
		for (int32_t stride = kParallelScoreThreads / 2; stride > 0; stride /= 2)
		{
			if (threadIdx.x < stride)
			{
				int32_t otherScore = sharedScores[threadIdx.x + stride];
				int32_t otherId = sharedIds[threadIdx.x + stride];
				if (betterScoreCandidate(otherScore, otherId,
										 sharedScores[threadIdx.x],
										 sharedIds[threadIdx.x]))
				{
					sharedScores[threadIdx.x] = otherScore;
					sharedIds[threadIdx.x] = otherId;
				}
			}
			__syncthreads();
		}
		if (threadIdx.x == 0)
		{
			int32_t maxScore = sharedScores[0];
			scoreTable[base + i] = max(maxScore, group.kmerSize);
			backtrackTable[base + i] = maxScore > group.kmerSize ?
									   sharedIds[0] : -1;
		}
		__syncthreads();
	}

	if (threadIdx.x != 0) return;
	for (int32_t i = 0; i < group.matchCount; ++i) orderScratch[base + i] = i;
	sortIndicesByScore(orderScratch + base, group.matchCount, scoreTable + base);

	int32_t proposalCount = 0;
	for (int32_t orderIdx = 0; orderIdx < group.matchCount; ++orderIdx)
	{
		int32_t chainStart = orderScratch[base + orderIdx];
		if (backtrackTable[base + chainStart] == -1) continue;
		int32_t lastMatch = chainStart;
		int32_t firstMatch = 0;
		int32_t chainLength = 0;
		int32_t pos = chainStart;
		while (pos != -1)
		{
			firstMatch = pos;
			++chainLength;
			int32_t newPos = backtrackTable[base + pos];
			backtrackTable[base + pos] = -1;
			pos = newPos;
		}

		OverlapRecord row;
		row.queryId = group.queryId;
		row.queryOrdinal = group.queryOrdinal;
		row.curBegin = matches[base + firstMatch].curPos;
		row.extBegin = matches[base + firstMatch].extPos;
		row.curLen = group.queryLen;
		row.extId = group.extId;
		row.extLen = group.extLen;
		row.curEnd = matches[base + lastMatch].curPos + group.kmerSize - 1;
		row.extEnd = matches[base + lastMatch].extPos + group.kmerSize - 1;
		row.score = scoreTable[base + lastMatch] -
					scoreTable[base + firstMatch] + group.kmerSize - 1;
		row.seqDivergence = 0.0f;
		row.chainLength = chainLength;
		if (!overlapTest(row, group.minOverlap)) continue;
		int32_t curRange = row.curEnd - row.curBegin;
		int32_t extRange = row.extEnd - row.extBegin;
		int32_t normLen = max(curRange, extRange);
		if (normLen <= 0) continue;
		float matchRate = static_cast<float>(chainLength) /
						  static_cast<float>(normLen);
		if (matchRate > 1.0f) matchRate = 1.0f;
		if (matchRate <= 0.0f) continue;
		row.seqDivergence = logf(1.0f / matchRate) /
							static_cast<float>(group.kmerSize);
		proposalRows[base + proposalCount] = row;
		++proposalCount;
	}
	proposalCounts[groupIdx] = proposalCount;
	sortOverlapsByScore(proposalRows + base, proposalCount);

	int32_t outputCount = 0;
	for (int32_t i = 0; i < proposalCount; ++i)
	{
		OverlapRecord row = proposalRows[base + i];
		bool isContained = false;
		for (int32_t j = 0; j < outputCount; ++j)
		{
			OverlapRecord primary = outputRows[group.outputOffset + j];
			if (containedBy(row, primary) && primary.score > row.score)
			{
				isContained = true;
				break;
			}
		}
		if (!isContained && row.seqDivergence < kMaxDivergence)
		{
			outputRows[group.outputOffset + outputCount] = row;
			++outputCount;
		}
	}
	outputCounts[groupIdx] = outputCount;
	atomicAdd(&status->outputRecords, outputCount);
}

void writeRawOverlapTsv(const std::string& path,
						const std::vector<QuerySummary>& queries,
						std::vector<OverlapRecord> rows)
{
	std::map<int64_t, int32_t> perQueryCounts;
	for (const auto& row : rows) perQueryCounts[row.queryId] += 1;
	std::map<int64_t, int32_t> perQueryOrder;

	std::ofstream output(path.c_str());
	if (!output)
	{
		throw std::runtime_error("can't open output TSV: " + path);
	}
	std::map<int64_t, int32_t> chainInputCounts;
	for (const auto& query : queries)
	{
		chainInputCounts[query.queryId] = query.chainInputCount;
	}

	output << "# schema=cuflye-read-to-graph-raw-overlap-v0\n";
	output << "query_id\tsource_order\traw_overlap_count\tchain_input_count\t"
			  "read_id\tread_begin\tread_end\tread_len\tedge_seq_id\t"
			  "edge_begin\tedge_end\tedge_len\tedge_id\tscore\t"
			  "seq_divergence\tpasses_chain_input_filter\n";
	output << std::setprecision(9);
	for (const auto& row : rows)
	{
		int32_t order = perQueryOrder[row.queryId]++;
		output << row.queryId << "\t"
			   << order << "\t"
			   << perQueryCounts[row.queryId] << "\t"
			   << chainInputCounts[row.queryId] << "\t"
			   << row.queryId << "\t"
			   << row.curBegin << "\t"
			   << row.curEnd << "\t"
			   << row.curLen << "\t"
			   << row.extId << "\t"
			   << row.extBegin << "\t"
			   << row.extEnd << "\t"
			   << row.extLen << "\t"
			   << 0 << "\t"
			   << row.score << "\t"
			   << row.seqDivergence << "\t"
			   << 0 << "\n";
	}
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
		   << "  \"schema\": \"cuflye-cuda-full-query-hit-replay-v0\",\n"
		   << "  \"status\": \"ok\",\n"
		   << "  \"backend\": \"cuda\",\n"
		   << "  \"kernel_mode\": \"" << jsonEscape(summary.kernelMode) << "\",\n"
		   << "  \"parallel_threads\": " << summary.parallelThreads << ",\n"
		   << "  \"repeat_count\": " << summary.repeatCount << ",\n"
		   << "  \"source_pack_dir\": \"" << jsonEscape(options.packDir) << "\",\n"
		   << "  \"output_tsv\": \"" << jsonEscape(options.outputTsv) << "\",\n"
		   << "  \"device\": " << summary.device << ",\n"
		   << "  \"device_name\": \"" << jsonEscape(summary.deviceName) << "\",\n"
		   << "  \"query_count\": " << summary.queryCount << ",\n"
		   << "  \"source_match_records\": " << summary.sourceMatchRecords << ",\n"
		   << "  \"source_ext_groups\": " << summary.extGroups << ",\n"
		   << "  \"active_ext_groups\": " << summary.activeGroups << ",\n"
		   << "  \"output_records\": " << summary.outputRecords << ",\n"
		   << "  \"max_supported_group_matches\": " << kMaxSupportedGroupMatches << ",\n"
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
		   << "  }";
	if (!summary.requestTimings.empty())
	{
		output << ",\n"
			   << "  \"request_timings_ms\": [\n";
		for (size_t i = 0; i < summary.requestTimings.size(); ++i)
		{
			const RequestTiming& timing = summary.requestTimings[i];
			output << "    {\n"
				   << "      \"request_ordinal\": " << i << ",\n"
				   << "      \"reset\": " << timing.resetMs << ",\n"
				   << "      \"kernel\": " << timing.kernelMs << ",\n"
				   << "      \"device_to_host\": " << timing.deviceToHostMs << ",\n"
				   << "      \"request_total\": " << timing.requestTotalMs << ",\n"
				   << "      \"output_records\": " << timing.outputRecords << "\n"
				   << "    }" << (i + 1 == summary.requestTimings.size() ? "\n" : ",\n");
		}
		output << "  ]";
	}
	output << "\n}\n";
}

void writeErrorJson(const std::string& path, const Options& options,
					const std::string& message)
{
	if (path.empty()) return;
	std::ofstream output(path.c_str());
	if (!output) return;
	output << "{\n"
		   << "  \"schema\": \"cuflye-cuda-full-query-hit-replay-v0\",\n"
		   << "  \"status\": \"error\",\n"
		   << "  \"backend\": \"cuda\",\n"
		   << "  \"kernel_mode\": \"" << jsonEscape(options.kernelMode) << "\",\n"
		   << "  \"repeat_count\": " << options.repeatCount << ",\n"
		   << "  \"source_pack_dir\": \"" << jsonEscape(options.packDir) << "\",\n"
		   << "  \"output_tsv\": \"" << jsonEscape(options.outputTsv) << "\",\n"
		   << "  \"error\": \"" << jsonEscape(message) << "\"\n"
		   << "}\n";
}

bool replaySessionCompatible(const ReplaySession& session, const Options& options)
{
	return session.initialized &&
		   session.options.packDir == options.packDir &&
		   session.options.device == options.device &&
		   session.options.kernelMode == options.kernelMode &&
		   session.options.hasMemoryBudget == options.hasMemoryBudget &&
		   (!options.hasMemoryBudget ||
			session.options.memoryBudgetBytes == options.memoryBudgetBytes);
}

void copySessionSummary(const ReplaySession& session, const Options& options,
						RunSummary& summary)
{
	summary.device = options.device;
	summary.kernelMode = options.kernelMode;
	summary.parallelThreads = options.kernelMode == "parallel-score" ?
							  kParallelScoreThreads : 1;
	summary.repeatCount = options.repeatCount;
	summary.parseMs = session.parseMs;
	summary.hostPackMs = session.hostPackMs;
	summary.deviceAllocationMs = session.deviceAllocationMs;
	summary.hostToDeviceMs = session.hostToDeviceMs;
	summary.queryCount = session.queries.size();
	summary.sourceMatchRecords = session.sourceMatchRecords;
	summary.extGroups = session.extGroups;
	summary.activeGroups = session.activeGroups;
	summary.requiredBytes = session.requiredBytes;
	summary.freeBytes = session.freeBytes;
	summary.totalBytes = session.totalBytes;
	summary.deviceName = session.deviceName;
}

void initializeReplaySession(const Options& options, ReplaySession& session)
{
	session = ReplaySession();
	session.options = options;
	session.options.outputTsv.clear();
	session.options.jsonOutput.clear();
	session.options.repeatCount = 1;

	auto parseStart = Clock::now();
	std::vector<std::pair<int64_t, std::string>> queryDirs =
		discoverQueryDirs(options.packDir);
	int32_t outputOffset = 0;
	for (const auto& item : queryDirs)
	{
		const std::string& queryDir = item.second;
		QueryParams params = loadQueryParams(queryDir);
		auto query = loadQuery(queryDir);
		std::map<int64_t, int32_t> edgeLengths = loadEdgeLengths(queryDir);
		std::vector<MatchRecord> matches =
			loadFullQueryHits(queryDir, query.first);
		QuerySummary querySummary;
		querySummary.queryId = query.first;
		querySummary.queryLen = query.second;
		querySummary.chainInputCount = loadOracleChainInputCount(queryDir);
		int32_t queryOrdinal = static_cast<int32_t>(session.queries.size());
		session.queries.push_back(querySummary);
		session.sourceMatchRecords += matches.size();

		size_t begin = 0;
		while (begin < matches.size())
		{
			size_t end = begin + 1;
			while (end < matches.size() &&
				   matches[end].extId == matches[begin].extId)
			{
				++end;
			}
			++session.extGroups;
			int64_t extId = matches[begin].extId;
			auto edgeIt = edgeLengths.find(extId);
			if (edgeIt == edgeLengths.end())
			{
				throw std::runtime_error(queryDir +
										 ": missing edge sequence for hit group");
			}
			std::vector<MatchRecord> group(matches.begin() + begin,
										   matches.begin() + end);
			if (prefilterGroup(group, edgeIt->second, params.minOverlap))
			{
				if (group.size() >
					static_cast<size_t>(kMaxSupportedGroupMatches))
				{
					throw std::runtime_error(
						"unsupported shape: group match count exceeds limit");
				}
				if (edgeIt->second > query.second)
				{
					std::sort(group.begin(), group.end(),
							  [](const MatchRecord& left,
								 const MatchRecord& right)
							  { return left.extPos < right.extPos; });
				}
				GroupRecord groupRecord;
				groupRecord.queryId = query.first;
				groupRecord.queryOrdinal = queryOrdinal;
				groupRecord.queryLen = query.second;
				groupRecord.extId = extId;
				groupRecord.extLen = edgeIt->second;
				groupRecord.matchOffset =
					static_cast<int32_t>(session.flatMatches.size());
				groupRecord.matchCount = static_cast<int32_t>(group.size());
				groupRecord.outputOffset = outputOffset;
				groupRecord.kmerSize = params.kmerSize;
				groupRecord.maxJump = params.maxJump;
				groupRecord.minOverlap = params.minOverlap;
				outputOffset += groupRecord.matchCount;
				session.flatMatches.insert(session.flatMatches.end(),
										  group.begin(), group.end());
				session.groups.push_back(groupRecord);
				++session.activeGroups;
			}
			begin = end;
		}
	}
	if (session.groups.empty())
	{
		throw std::runtime_error("unsupported shape: no active replay groups");
	}
	session.parseMs = elapsedMs(parseStart, Clock::now());

	auto hostPackStart = Clock::now();
	session.scoreTable.assign(session.flatMatches.size(), 0);
	session.backtrackTable.assign(session.flatMatches.size(), -1);
	session.orderScratch.assign(session.flatMatches.size(), 0);
	session.proposalRows.assign(session.flatMatches.size(), OverlapRecord{});
	session.proposalCounts.assign(session.groups.size(), 0);
	session.outputRows.assign(session.flatMatches.size(), OverlapRecord{});
	session.outputCounts.assign(session.groups.size(), 0);
	session.hostPackMs = elapsedMs(hostPackStart, Clock::now());

	cuflye::cuda_raii::checkCuda(
		cudaSetDevice(options.device), "select CUDA device");
	cudaDeviceProp props{};
	cuflye::cuda_raii::checkCuda(
		cudaGetDeviceProperties(&props, options.device),
		"read CUDA device properties");
	session.deviceName = props.name;
	cuflye::cuda_raii::checkCuda(
		cudaMemGetInfo(&session.freeBytes, &session.totalBytes),
		"read CUDA memory info");

	size_t requiredBytes = 0;
	requiredBytes = checkedAdd(
		requiredBytes,
		checkedBytes(session.flatMatches.size(), sizeof(MatchRecord), "matches"),
		"required bytes");
	requiredBytes = checkedAdd(
		requiredBytes,
		checkedBytes(session.groups.size(), sizeof(GroupRecord), "groups"),
		"required bytes");
	requiredBytes = checkedAdd(
		requiredBytes,
		checkedBytes(session.scoreTable.size(), sizeof(int32_t), "score table"),
		"required bytes");
	requiredBytes = checkedAdd(
		requiredBytes,
		checkedBytes(session.backtrackTable.size(), sizeof(int32_t),
					 "backtrack table"),
		"required bytes");
	requiredBytes = checkedAdd(
		requiredBytes,
		checkedBytes(session.orderScratch.size(), sizeof(int32_t),
					 "order scratch"),
		"required bytes");
	requiredBytes = checkedAdd(
		requiredBytes,
		checkedBytes(session.proposalRows.size(), sizeof(OverlapRecord),
					 "proposals"),
		"required bytes");
	requiredBytes = checkedAdd(
		requiredBytes,
		checkedBytes(session.outputRows.size(), sizeof(OverlapRecord),
					 "output rows"),
		"required bytes");
	requiredBytes = checkedAdd(
		requiredBytes,
		checkedBytes(session.proposalCounts.size(), sizeof(int32_t),
					 "proposal counts"),
		"required bytes");
	requiredBytes = checkedAdd(
		requiredBytes,
		checkedBytes(session.outputCounts.size(), sizeof(int32_t),
					 "output counts"),
		"required bytes");
	requiredBytes = checkedAdd(requiredBytes, sizeof(DeviceStatus),
							   "required bytes");
	session.requiredBytes = requiredBytes;
	if (options.hasMemoryBudget &&
		session.requiredBytes > options.memoryBudgetBytes)
	{
		throw std::runtime_error("required bytes exceed memory budget");
	}

	auto allocStart = Clock::now();
	session.dMatches.allocate(
		checkedBytes(session.flatMatches.size(), sizeof(MatchRecord), "dMatches"),
		"full query-hit matches");
	session.dGroups.allocate(
		checkedBytes(session.groups.size(), sizeof(GroupRecord), "dGroups"),
		"full query-hit groups");
	session.dScore.allocate(
		checkedBytes(session.scoreTable.size(), sizeof(int32_t), "dScore"),
		"full query-hit score table");
	session.dBacktrack.allocate(
		checkedBytes(session.backtrackTable.size(), sizeof(int32_t), "dBacktrack"),
		"full query-hit backtrack table");
	session.dOrder.allocate(
		checkedBytes(session.orderScratch.size(), sizeof(int32_t), "dOrder"),
		"full query-hit order scratch");
	session.dProposals.allocate(
		checkedBytes(session.proposalRows.size(), sizeof(OverlapRecord),
					 "dProposals"),
		"full query-hit proposals");
	session.dProposalCounts.allocate(
		checkedBytes(session.proposalCounts.size(), sizeof(int32_t),
					 "dProposalCounts"),
		"full query-hit proposal counts");
	session.dOutput.allocate(
		checkedBytes(session.outputRows.size(), sizeof(OverlapRecord), "dOutput"),
		"full query-hit output rows");
	session.dOutputCounts.allocate(
		checkedBytes(session.outputCounts.size(), sizeof(int32_t), "dOutputCounts"),
		"full query-hit output counts");
	session.dStatus.allocate(sizeof(DeviceStatus), "full query-hit status");
	session.deviceAllocationMs = elapsedMs(allocStart, Clock::now());

	auto h2dStart = Clock::now();
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(session.dMatches.get(), session.flatMatches.data(),
				   checkedBytes(session.flatMatches.size(), sizeof(MatchRecord),
								"copy matches"),
				   cudaMemcpyHostToDevice),
		"copy full query-hit matches to device");
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(session.dGroups.get(), session.groups.data(),
				   checkedBytes(session.groups.size(), sizeof(GroupRecord),
								"copy groups"),
				   cudaMemcpyHostToDevice),
		"copy full query-hit groups to device");
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(session.dProposalCounts.get(), session.proposalCounts.data(),
				   checkedBytes(session.proposalCounts.size(), sizeof(int32_t),
								"copy proposal counts"),
				   cudaMemcpyHostToDevice),
		"initialize proposal counts");
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(session.dOutputCounts.get(), session.outputCounts.data(),
				   checkedBytes(session.outputCounts.size(), sizeof(int32_t),
								"copy output counts"),
				   cudaMemcpyHostToDevice),
		"initialize output counts");
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(session.dStatus.get(), &session.zeroStatus,
				   sizeof(DeviceStatus), cudaMemcpyHostToDevice),
		"initialize full query-hit device status");
	session.hostToDeviceMs = elapsedMs(h2dStart, Clock::now());
	session.initialized = true;
}

RequestTiming runReplayKernel(ReplaySession& session, const std::string& kernelMode)
{
	RequestTiming requestTiming;
	auto requestStart = Clock::now();

	auto resetStart = Clock::now();
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(session.dStatus.get(), &session.zeroStatus,
				   sizeof(DeviceStatus), cudaMemcpyHostToDevice),
		"reset full query-hit device status");
	requestTiming.resetMs = elapsedMs(resetStart, Clock::now());

	auto kernelStart = Clock::now();
	if (kernelMode == "serial")
	{
		replayFullQueryHitGroupsKernel
			<<<static_cast<int32_t>(session.groups.size()), 1>>>(
				session.dMatches.get(), session.dGroups.get(),
				static_cast<int32_t>(session.groups.size()),
				session.dScore.get(), session.dBacktrack.get(),
				session.dOrder.get(), session.dProposals.get(),
				session.dProposalCounts.get(), session.dOutput.get(),
				session.dOutputCounts.get(), session.dStatus.get());
	}
	else
	{
		replayFullQueryHitGroupsParallelScoreKernel
			<<<static_cast<int32_t>(session.groups.size()), kParallelScoreThreads>>>(
				session.dMatches.get(), session.dGroups.get(),
				static_cast<int32_t>(session.groups.size()),
				session.dScore.get(), session.dBacktrack.get(),
				session.dOrder.get(), session.dProposals.get(),
				session.dProposalCounts.get(), session.dOutput.get(),
				session.dOutputCounts.get(), session.dStatus.get());
	}
	cuflye::cuda_raii::checkCuda(
		cudaGetLastError(), "launch full query-hit replay kernel");
	cuflye::cuda_raii::checkCuda(
		cudaDeviceSynchronize(), "synchronize full query-hit replay kernel");
	requestTiming.kernelMs = elapsedMs(kernelStart, Clock::now());

	auto d2hStart = Clock::now();
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(session.outputRows.data(), session.dOutput.get(),
				   checkedBytes(session.outputRows.size(), sizeof(OverlapRecord),
								"copy output rows"),
				   cudaMemcpyDeviceToHost),
		"copy full query-hit output rows to host");
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(session.outputCounts.data(), session.dOutputCounts.get(),
				   checkedBytes(session.outputCounts.size(), sizeof(int32_t),
								"copy output counts"),
				   cudaMemcpyDeviceToHost),
		"copy full query-hit output counts to host");
	cuflye::cuda_raii::checkCuda(
		cudaMemcpy(&session.lastStatus, session.dStatus.get(),
				   sizeof(DeviceStatus), cudaMemcpyDeviceToHost),
		"copy full query-hit status to host");
	requestTiming.deviceToHostMs = elapsedMs(d2hStart, Clock::now());
	requestTiming.requestTotalMs = elapsedMs(requestStart, Clock::now());
	requestTiming.outputRecords = session.lastStatus.outputRecords;
	if (session.lastStatus.errorCode != 0)
	{
		throw std::runtime_error("device full query-hit kernel reported an error");
	}
	return requestTiming;
}

std::vector<OverlapRecord> collectFinalRows(ReplaySession& session)
{
	std::vector<OverlapRecord> finalRows;
	finalRows.reserve(static_cast<size_t>(session.lastStatus.outputRecords));
	for (size_t groupIdx = 0; groupIdx < session.groups.size(); ++groupIdx)
	{
		int32_t count = session.outputCounts[groupIdx];
		if (count < 0 || count > session.groups[groupIdx].matchCount)
		{
			throw std::runtime_error("device output count is outside group bounds");
		}
		std::vector<OverlapRecord> groupRows;
		groupRows.reserve(static_cast<size_t>(count));
		for (int32_t pos = 0; pos < count; ++pos)
		{
			groupRows.push_back(
				session.outputRows[session.groups[groupIdx].outputOffset + pos]);
		}
		std::sort(groupRows.begin(), groupRows.end(),
				  [](const OverlapRecord& left, const OverlapRecord& right)
				  { return left.score > right.score; });
		finalRows.insert(finalRows.end(), groupRows.begin(), groupRows.end());
	}
	if (finalRows.size() !=
		static_cast<size_t>(session.lastStatus.outputRecords))
	{
		throw std::runtime_error("device output count mismatch");
	}
	for (auto& query : session.queries)
	{
		query.outputRecords = 0;
	}
	for (const auto& row : finalRows)
	{
		if (row.queryOrdinal < 0 ||
			row.queryOrdinal >= static_cast<int32_t>(session.queries.size()))
		{
			throw std::runtime_error("device output row has invalid query ordinal");
		}
		session.queries[row.queryOrdinal].outputRecords += 1;
	}
	return finalRows;
}

RunSummary runReplayWithSession(const Options& options, ReplaySession& session,
								bool allowReuse)
{
	auto totalStart = Clock::now();
	if (!allowReuse || !replaySessionCompatible(session, options))
	{
		if (allowReuse && session.initialized)
		{
			throw std::runtime_error(
				"full query-hit worker requires stable source-pack/device/kernel shape");
		}
		initializeReplaySession(options, session);
	}

	RunSummary summary;
	copySessionSummary(session, options, summary);
	for (int requestIdx = 0; requestIdx < options.repeatCount; ++requestIdx)
	{
		summary.requestTimings.push_back(
			runReplayKernel(session, options.kernelMode));
	}
	const RequestTiming& finalRequest = summary.requestTimings.back();
	summary.kernelMs = finalRequest.kernelMs;
	summary.deviceToHostMs = finalRequest.deviceToHostMs;
	summary.outputRecords = finalRequest.outputRecords;

	std::vector<OverlapRecord> finalRows = collectFinalRows(session);
	summary.outputRecords = finalRows.size();

	auto writeStart = Clock::now();
	writeRawOverlapTsv(options.outputTsv, session.queries, finalRows);
	summary.writeMs = elapsedMs(writeStart, Clock::now());
	summary.totalMs = elapsedMs(totalStart, Clock::now());
	return summary;
}

WorkerRequest parseWorkerRequestObject(const std::string& text)
{
	std::map<std::string, std::string> fields = parseFlatJsonObject(text);
	WorkerRequest request;
	request.schema = requireJsonField(fields, "schema");
	request.requestId = requireJsonField(fields, "request_id");
	request.responseJson = requireJsonField(fields, "response_json");
	request.adapterMode = requireJsonField(fields, "adapter_mode");
	request.rawOverlapAbi = requireJsonField(fields, "raw_overlap_abi");
	request.options.packDir = requireJsonField(fields, "source_pack_dir");
	request.options.outputTsv = requireJsonField(fields, "output_tsv");
	request.options.kernelMode = requireJsonField(fields, "kernel_mode");
	request.options.device =
		parseI32(requireJsonField(fields, "device"), "device");
	request.options.repeatCount = 1;
	request.options.jsonOutput = optionalJsonField(fields, "debug_json_output");
	std::string memoryBudget = optionalJsonField(fields, "memory_budget_bytes");
	if (!memoryBudget.empty() && memoryBudget != "null")
	{
		request.options.hasMemoryBudget = true;
		request.options.memoryBudgetBytes =
			parseWorkerUnsigned(memoryBudget, "memory_budget_bytes");
	}
	std::string expectedOutputRecords =
		optionalJsonField(fields, "expected_output_records");
	if (!expectedOutputRecords.empty() && expectedOutputRecords != "null")
	{
		request.hasExpectedOutputRecords = true;
		request.expectedOutputRecords = static_cast<size_t>(
			parseWorkerUnsigned(expectedOutputRecords, "expected_output_records"));
	}
	return request;
}

std::vector<WorkerRequest> loadWorkerRequests(const Options& cliOptions)
{
	std::vector<WorkerRequest> requests;
	if (!cliOptions.workerRequestJson.empty())
	{
		requests.push_back(parseWorkerRequestObject(
			readFile(cliOptions.workerRequestJson)));
		return requests;
	}

	std::ifstream input(cliOptions.workerRequestsJsonl.c_str());
	if (!input)
	{
		throw std::runtime_error(
			"can't read full query-hit worker requests JSONL: " +
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
			requests.push_back(parseWorkerRequestObject(stripped));
		}
		catch (const std::exception& exc)
		{
			throw std::runtime_error(cliOptions.workerRequestsJsonl + ":" +
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

void validateWorkerRequest(const WorkerRequest& request)
{
	if (request.schema != "cuflye-full-query-hit-worker-request-v0")
	{
		throw std::runtime_error("unsupported full query-hit worker request schema");
	}
	if (request.adapterMode != "full-query-hit-replay-v0")
	{
		throw std::runtime_error("unsupported full query-hit worker adapter_mode");
	}
	if (request.rawOverlapAbi != "cuflye-read-to-graph-raw-overlap-v0")
	{
		throw std::runtime_error("unsupported full query-hit worker raw_overlap_abi");
	}
	if (request.options.kernelMode != "parallel-score")
	{
		throw std::runtime_error(
			"full query-hit worker supports parallel-score kernel mode only");
	}
	if (request.options.outputTsv.empty())
	{
		throw std::runtime_error("full query-hit worker output_tsv is required");
	}
}

std::string buildWorkerResponseJson(const WorkerRequest& request,
									const RunSummary& summary,
									size_t requestOrdinal,
									bool workerContextWarm,
									double workerContextSetupMs,
									double workerUptimeMs,
									double requestTotalMs)
{
	double requestParseMs = workerContextWarm ? 0.0 : summary.parseMs;
	double requestHostPackMs = workerContextWarm ? 0.0 : summary.hostPackMs;
	double requestDeviceAllocationMs =
		workerContextWarm ? 0.0 : summary.deviceAllocationMs;
	double requestHostToDeviceMs = workerContextWarm ? 0.0 : summary.hostToDeviceMs;
	std::ostringstream json;
	json << std::fixed << std::setprecision(6);
	json << "{\n"
		 << "  \"schema\": \"cuflye-full-query-hit-worker-response-v0\",\n"
		 << "  \"request_id\": \"" << jsonEscape(request.requestId) << "\",\n"
		 << "  \"status\": \"ok\",\n"
		 << "  \"request_ordinal\": " << requestOrdinal << ",\n"
		 << "  \"worker_cuda_context_warm\": "
		 << (workerContextWarm ? "true" : "false") << ",\n"
		 << "  \"worker_context_setup_ms\": " << workerContextSetupMs << ",\n"
		 << "  \"adapter_mode\": \"full-query-hit-replay-v0\",\n"
		 << "  \"raw_overlap_abi\": \"cuflye-read-to-graph-raw-overlap-v0\",\n"
		 << "  \"kernel_mode\": \"" << jsonEscape(summary.kernelMode) << "\",\n"
		 << "  \"parallel_threads\": " << summary.parallelThreads << ",\n"
		 << "  \"source_pack_dir\": \""
		 << jsonEscape(request.options.packDir) << "\",\n"
		 << "  \"output_tsv\": \"" << jsonEscape(request.options.outputTsv) << "\",\n"
		 << "  \"device\": " << summary.device << ",\n"
		 << "  \"device_name\": \"" << jsonEscape(summary.deviceName) << "\",\n"
		 << "  \"query_count\": " << summary.queryCount << ",\n"
		 << "  \"source_match_records\": " << summary.sourceMatchRecords << ",\n"
		 << "  \"source_ext_groups\": " << summary.extGroups << ",\n"
		 << "  \"active_ext_groups\": " << summary.activeGroups << ",\n"
		 << "  \"output_records\": " << summary.outputRecords << ",\n"
		 << "  \"required_bytes\": " << summary.requiredBytes << ",\n"
		 << "  \"timing_ms\": {\n"
		 << "    \"worker_uptime\": " << workerUptimeMs << ",\n"
		 << "    \"request_total\": " << requestTotalMs << ",\n"
		 << "    \"parse\": " << requestParseMs << ",\n"
		 << "    \"host_pack\": " << requestHostPackMs << ",\n"
		 << "    \"device_allocation\": " << requestDeviceAllocationMs << ",\n"
		 << "    \"host_to_device\": " << requestHostToDeviceMs << ",\n"
		 << "    \"kernel\": " << summary.kernelMs << ",\n"
		 << "    \"device_to_host\": " << summary.deviceToHostMs << ",\n"
		 << "    \"write_output\": " << summary.writeMs << "\n"
		 << "  }\n"
		 << "}\n";
	return json.str();
}

std::string buildWorkerErrorJson(const WorkerRequest& request,
								 size_t requestOrdinal,
								 const std::string& message)
{
	std::ostringstream json;
	json << "{\n"
		 << "  \"schema\": \"cuflye-full-query-hit-worker-response-v0\",\n"
		 << "  \"request_id\": \"" << jsonEscape(request.requestId) << "\",\n"
		 << "  \"status\": \"error\",\n"
		 << "  \"request_ordinal\": " << requestOrdinal << ",\n"
		 << "  \"error_code\": \"request-failed\",\n"
		 << "  \"error_message\": \"" << jsonEscape(message) << "\"\n"
		 << "}\n";
	return json.str();
}

bool executeWorkerRequest(const WorkerRequest& request,
						  size_t requestOrdinal,
						  Clock::time_point workerStart,
						  ReplaySession& session,
						  double& workerContextSetupMs)
{
	auto requestStart = Clock::now();
	bool hadSession = session.initialized;
	try
	{
		validateWorkerRequest(request);
		if (request.hasExpectedOutputRecords && request.expectedOutputRecords == 0)
		{
			throw std::runtime_error(
				"full query-hit worker expected_output_records must be > 0");
		}
		if (!session.initialized)
		{
			auto setupStart = Clock::now();
			initializeReplaySession(request.options, session);
			workerContextSetupMs = elapsedMs(setupStart, Clock::now());
		}
		else if (!replaySessionCompatible(session, request.options))
		{
			throw std::runtime_error(
				"full query-hit worker requires stable source-pack/device/kernel shape");
		}

		RunSummary summary =
			runReplayWithSession(request.options, session, true);
		if (request.hasExpectedOutputRecords &&
			summary.outputRecords != request.expectedOutputRecords)
		{
			throw std::runtime_error("full query-hit worker output count mismatch");
		}
		double requestTotalMs = elapsedMs(requestStart, Clock::now());
		double workerUptimeMs = elapsedMs(workerStart, Clock::now());
		std::string response = buildWorkerResponseJson(
			request, summary, requestOrdinal, hadSession, workerContextSetupMs,
			workerUptimeMs, requestTotalMs);
		writeTextFile(request.responseJson, response);
		std::cout << response;
		return true;
	}
	catch (const std::exception& exc)
	{
		std::string response =
			buildWorkerErrorJson(request, requestOrdinal, exc.what());
		if (!request.responseJson.empty()) writeTextFile(request.responseJson, response);
		std::cout << response;
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

std::vector<std::string> listSessionReadyFiles(const std::string& inbox)
{
	std::vector<std::string> readyFiles;
	std::unique_ptr<DIR, int(*)(DIR*)> dir(::opendir(inbox.c_str()), ::closedir);
	if (!dir)
	{
		if (errno == ENOENT) return readyFiles;
		throw std::runtime_error("can't read full query-hit worker session inbox: " +
								 inbox + ": " + std::strerror(errno));
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

double initializeWorkerDeviceContext(const Options& options,
									 std::string& deviceName,
									 size_t& freeBytes,
									 size_t& totalBytes)
{
	auto contextStart = Clock::now();
	cuflye::cuda_raii::checkCuda(cudaSetDevice(options.device),
								 "set full query-hit worker device");
	cudaDeviceProp props{};
	cuflye::cuda_raii::checkCuda(
		cudaGetDeviceProperties(&props, options.device),
		"get full query-hit worker device properties");
	deviceName = props.name;
	cuflye::cuda_raii::checkCuda(cudaMemGetInfo(&freeBytes, &totalBytes),
								 "query full query-hit worker memory");
	return elapsedMs(contextStart, Clock::now());
}

void writeWorkerSessionStateJson(const std::string& path,
								 const Options& options,
								 const std::string& status,
								 size_t processedRequests,
								 double workerContextSetupMs,
								 const std::string& deviceName,
								 size_t freeBytes,
								 size_t totalBytes,
								 const ReplaySession& session)
{
	std::ostringstream json;
	json << std::fixed << std::setprecision(6);
	json << "{\n"
		 << "  \"schema\": \"cuflye-full-query-hit-worker-session-v0\",\n"
		 << "  \"status\": \"" << jsonEscape(status) << "\",\n"
		 << "  \"worker_session_dir\": \""
		 << jsonEscape(options.workerSessionDir) << "\",\n"
		 << "  \"worker_session_max_requests\": "
		 << options.workerSessionMaxRequests << ",\n"
		 << "  \"worker_session_processed_requests\": "
		 << processedRequests << ",\n"
		 << "  \"worker_session_poll_ms\": "
		 << options.workerSessionPollMs << ",\n"
		 << "  \"worker_session_timeout_ms\": "
		 << options.workerSessionTimeoutMs << ",\n"
		 << "  \"worker_context_setup_ms\": " << workerContextSetupMs << ",\n"
		 << "  \"worker_replay_session_initialized\": "
		 << (session.initialized ? "true" : "false") << ",\n"
		 << "  \"worker_device_arena_enabled\": true,\n"
		 << "  \"worker_device_arena_capacity_bytes\": "
		 << (session.initialized ? session.requiredBytes : 0) << ",\n"
		 << "  \"device\": " << options.device << ",\n"
		 << "  \"device_name\": \"" << jsonEscape(deviceName) << "\",\n"
		 << "  \"free_bytes\": " << freeBytes << ",\n"
		 << "  \"total_bytes\": " << totalBytes << ",\n"
		 << "  \"pid\": " << static_cast<long long>(::getpid()) << "\n"
		 << "}\n";
	writeTextFile(path, json.str());
}

int runWorkerSessionMain(const Options& cliOptions)
{
	ensureDirectory(cliOptions.workerSessionDir);
	ensureDirectory(sessionInboxDir(cliOptions));
	ensureDirectory(sessionProcessingDir(cliOptions));
	ensureDirectory(sessionDoneDir(cliOptions));

	ReplaySession session;
	double workerContextSetupMs = 0.0;
	auto workerStart = Clock::now();
	std::string deviceName;
	size_t freeBytes = 0;
	size_t totalBytes = 0;
	double cudaContextSetupMs = initializeWorkerDeviceContext(
		cliOptions, deviceName, freeBytes, totalBytes);
	writeWorkerSessionStateJson(
		joinPath(cliOptions.workerSessionDir, "session-ready.json"),
		cliOptions, "ready", 0, cudaContextSetupMs, deviceName, freeBytes,
		totalBytes, session);

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
				writeWorkerSessionStateJson(
					joinPath(cliOptions.workerSessionDir, "session-error.json"),
					cliOptions, "timeout", processedRequests,
					workerContextSetupMs > 0.0 ? workerContextSetupMs :
												  cudaContextSetupMs,
					deviceName, freeBytes, totalBytes, session);
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
		std::string donePath =
			joinPath(sessionDoneDir(cliOptions), readyName + ".done");
		renameFile(readyPath, processingPath);
		std::string requestJsonPath = trim(readFile(processingPath));
		if (requestJsonPath.empty())
		{
			writeTextFile(donePath, "status=error\nerror=empty request path\n");
			writeWorkerSessionStateJson(
				joinPath(cliOptions.workerSessionDir, "session-error.json"),
				cliOptions, "error", processedRequests,
				workerContextSetupMs > 0.0 ? workerContextSetupMs :
											  cudaContextSetupMs,
				deviceName, freeBytes, totalBytes, session);
			return 1;
		}

		WorkerRequest request;
		try
		{
			request = parseWorkerRequestObject(readFile(requestJsonPath));
		}
		catch (const std::exception& exc)
		{
			writeTextFile(donePath, "status=error\nrequest_json=" +
								  requestJsonPath + "\nerror=" + exc.what() + "\n");
			writeWorkerSessionStateJson(
				joinPath(cliOptions.workerSessionDir, "session-error.json"),
				cliOptions, "error", processedRequests,
				workerContextSetupMs > 0.0 ? workerContextSetupMs :
											  cudaContextSetupMs,
				deviceName, freeBytes, totalBytes, session);
			return 1;
		}

		++processedRequests;
		if (request.options.device != cliOptions.device)
		{
			std::string message =
				"full query-hit worker session request device does not match "
				"session device";
			writeTextFile(request.responseJson,
						  buildWorkerErrorJson(request, processedRequests, message));
			writeTextFile(donePath, "status=error\nrequest_json=" +
								  requestJsonPath + "\nerror=" + message + "\n");
			writeWorkerSessionStateJson(
				joinPath(cliOptions.workerSessionDir, "session-error.json"),
				cliOptions, "error", processedRequests,
				workerContextSetupMs > 0.0 ? workerContextSetupMs :
											  cudaContextSetupMs,
				deviceName, freeBytes, totalBytes, session);
			return 1;
		}

		bool ok = executeWorkerRequest(request, processedRequests, workerStart,
									   session, workerContextSetupMs);
		writeTextFile(donePath, std::string("status=") + (ok ? "ok" : "error") +
							  "\nrequest_json=" + requestJsonPath + "\n");
		if (!ok)
		{
			writeWorkerSessionStateJson(
				joinPath(cliOptions.workerSessionDir, "session-error.json"),
				cliOptions, "error", processedRequests,
				workerContextSetupMs > 0.0 ? workerContextSetupMs :
											  cudaContextSetupMs,
				deviceName, freeBytes, totalBytes, session);
			return 1;
		}
	}

	writeWorkerSessionStateJson(
		joinPath(cliOptions.workerSessionDir, "session-complete.json"),
		cliOptions, "complete", processedRequests,
		workerContextSetupMs > 0.0 ? workerContextSetupMs : cudaContextSetupMs,
		deviceName, freeBytes, totalBytes, session);
	return 0;
}

int runWorkerMain(const Options& cliOptions)
{
	if (!cliOptions.workerSessionDir.empty())
	{
		return runWorkerSessionMain(cliOptions);
	}
	std::vector<WorkerRequest> requests = loadWorkerRequests(cliOptions);
	ReplaySession session;
	double workerContextSetupMs = 0.0;
	auto workerStart = Clock::now();
	for (size_t idx = 0; idx < requests.size(); ++idx)
	{
		bool ok = executeWorkerRequest(requests[idx], idx + 1, workerStart,
									   session, workerContextSetupMs);
		if (!ok) return 1;
	}
	return 0;
}

int runDirectMain(const Options& options)
{
	ReplaySession session;
	RunSummary summary = runReplayWithSession(options, session, false);
	writeJson(options.jsonOutput, options, summary);
	return 0;
}
}

int main(int argc, char** argv)
{
	Options options;
	try
	{
		options = parseOptions(argc, argv);
		if (!options.workerRequestJson.empty() ||
			!options.workerRequestsJsonl.empty() ||
			!options.workerSessionDir.empty())
		{
			return runWorkerMain(options);
		}
		return runDirectMain(options);
	}
	catch (const std::exception& exc)
	{
		writeErrorJson(options.jsonOutput, options, exc.what());
		std::cerr << "error: " << exc.what() << "\n";
		return 2;
	}
}
