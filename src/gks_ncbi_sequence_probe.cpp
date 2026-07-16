#include <ncbi_pch.hpp>

#include <corelib/ncbiapp.hpp>
#include <corelib/ncbiargs.hpp>
#include <objects/seqloc/Seq_id.hpp>
#include <objects/seq/seq_id_handle.hpp>
#include <objmgr/bioseq_handle.hpp>
#include <objmgr/object_manager.hpp>
#include <objmgr/scope.hpp>
#include <objmgr/seq_vector.hpp>
#include <objtools/data_loaders/asn_cache/asn_cache_loader.hpp>
#include <objtools/data_loaders/genbank/gbloader.hpp>

#include <algorithm>
#include <chrono>
#include <cctype>
#include <fstream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <vector>

USING_NCBI_SCOPE;
USING_SCOPE(objects);

namespace {

struct SRequest {
    string request_id;
    string accession;
    TSeqPos start = 0;
    TSeqPos end = 0;
    string expected_ref;
};

string JsonEscape(const string& value)
{
    ostringstream out;
    for (unsigned char c : value) {
        switch (c) {
        case '"': out << "\\\""; break;
        case '\\': out << "\\\\"; break;
        case '\b': out << "\\b"; break;
        case '\f': out << "\\f"; break;
        case '\n': out << "\\n"; break;
        case '\r': out << "\\r"; break;
        case '\t': out << "\\t"; break;
        default:
            if (c < 0x20) {
                static const char hex[] = "0123456789abcdef";
                out << "\\u00" << hex[c >> 4] << hex[c & 0xf];
            } else {
                out << static_cast<char>(c);
            }
        }
    }
    return out.str();
}

string Upper(string value)
{
    transform(value.begin(), value.end(), value.begin(),
              [](unsigned char c) { return static_cast<char>(toupper(c)); });
    return value;
}

vector<string> SplitTabs(const string& line)
{
    vector<string> fields;
    size_t begin = 0;
    while (true) {
        const size_t tab = line.find('\t', begin);
        fields.push_back(line.substr(begin, tab == string::npos ? tab : tab - begin));
        if (tab == string::npos) break;
        begin = tab + 1;
    }
    return fields;
}

TSeqPos ParsePosition(const string& value, const char* name)
{
    if (value.empty() || value[0] == '-') {
        throw runtime_error(string(name) + " must be a non-negative integer");
    }
    size_t used = 0;
    const unsigned long long parsed = stoull(value, &used);
    if (used != value.size() || parsed > numeric_limits<TSeqPos>::max()) {
        throw runtime_error(string("invalid ") + name + ": " + value);
    }
    return static_cast<TSeqPos>(parsed);
}

vector<SRequest> ReadRequests(const string& path)
{
    unique_ptr<istream> owned;
    istream* in = &cin;
    if (path != "-") {
        owned.reset(new ifstream(path));
        in = owned.get();
        if (!*in) throw runtime_error("cannot open requests file: " + path);
    }

    vector<SRequest> requests;
    string line;
    size_t line_number = 0;
    while (getline(*in, line)) {
        ++line_number;
        if (line.empty() || line[0] == '#') continue;
        const vector<string> fields = SplitTabs(line);
        if (line_number == 1 && fields.size() >= 4 && fields[0] == "request_id") continue;
        if (fields.size() != 5) {
            throw runtime_error("requests line " + NStr::NumericToString(line_number) +
                                " must have five tab-separated fields");
        }
        SRequest request;
        request.request_id = fields[0];
        request.accession = fields[1];
        request.start = ParsePosition(fields[2], "start");
        request.end = ParsePosition(fields[3], "end");
        request.expected_ref = Upper(fields[4]);
        if (request.request_id.empty() || request.accession.empty()) {
            throw runtime_error("request_id and accession must not be empty");
        }
        if (request.end < request.start) throw runtime_error("end is smaller than start");
        CSeq_id validated(request.accession);
        requests.push_back(request);
    }
    if (requests.empty()) throw runtime_error("requests file contains no requests");
    return requests;
}

string AliasesJson(CScope& scope, const CSeq_id_Handle& idh)
{
    ostringstream out;
    out << '[';
    bool first = true;
    for (const auto& alias : scope.GetIds(idh)) {
        if (!first) out << ',';
        first = false;
        out << '"' << JsonEscape(alias.AsString()) << '"';
    }
    out << ']';
    return out.str();
}

} // namespace

class CGksNcbiSequenceProbe : public CNcbiApplication
{
public:
    void Init(void) override;
    int Run(void) override;
};

void CGksNcbiSequenceProbe::Init(void)
{
    unique_ptr<CArgDescriptions> args(new CArgDescriptions);
    args->SetUsageContext(GetArguments().GetProgramBasename(),
                          "Retrieve 0-based half-open sequence slices with explicit NCBI loaders");
    args->AddKey("mode", "Mode", "genbank, asn, or hybrid", CArgDescriptions::eString);
    args->SetConstraint("mode", &(*new CArgAllow_Strings, "genbank", "asn", "hybrid"));
    args->AddOptionalKey("asn-cache", "Path", "ASN cache path", CArgDescriptions::eString);
    args->AddKey("requests", "TSV", "Request TSV path, or - for stdin", CArgDescriptions::eString);
    args->AddDefaultKey("output", "JSONL", "Output JSONL path, or - for stdout",
                        CArgDescriptions::eString, "-");
    args->AddDefaultKey("repeat", "Count", "Measured iterations", CArgDescriptions::eInteger, "1");
    args->SetConstraint("repeat", new CArgAllow_Integers(1, kMax_Int));
    args->AddDefaultKey("warmup", "Count", "Unreported warmup iterations",
                        CArgDescriptions::eInteger, "0");
    args->SetConstraint("warmup", new CArgAllow_Integers(0, kMax_Int));
    args->AddFlag("allow-remote", "Permit registration of the GenBank loader");
    args->AddFlag("print-sequence", "Include the requested sequence in observed_ref");
    args->AddFlag("fail-on-mismatch", "Return nonzero when expected REF differs");
    SetupArgDescriptions(args.release());
}

int CGksNcbiSequenceProbe::Run(void)
{
    const CArgs& args = GetArgs();
    const string mode = args["mode"].AsString();
    const bool allow_remote = args["allow-remote"];
    const bool print_sequence = args["print-sequence"];
    const bool fail_on_mismatch = args["fail-on-mismatch"];

    if ((mode == "genbank" || mode == "hybrid") && !allow_remote && mode == "genbank") {
        NCBI_THROW(CArgException, eConstraint, "genbank mode requires -allow-remote");
    }
    if ((mode == "asn" || mode == "hybrid") && !args["asn-cache"]) {
        NCBI_THROW(CArgException, eNoArg, "asn/hybrid mode requires -asn-cache");
    }

    unique_ptr<ostream> owned_output;
    ostream* output = &cout;
    const string output_path = args["output"].AsString();
    if (output_path != "-") {
        owned_output.reset(new ofstream(output_path));
        output = owned_output.get();
        if (!*output) throw runtime_error("cannot open output file: " + output_path);
    }

    const vector<SRequest> requests = ReadRequests(args["requests"].AsString());
    CRef<CObjectManager> object_manager = CObjectManager::GetInstance();
    CRef<CScope> scope(new CScope(*object_manager));

    if (mode == "asn" || mode == "hybrid") {
        const string path = args["asn-cache"].AsString();
        auto info = CAsnCache_DataLoader::RegisterInObjectManager(
            *object_manager, path, CObjectManager::eNonDefault, 1);
        scope->AddDataLoader(info.GetLoader()->GetName(), 1);
    }
    if (mode == "genbank" || (mode == "hybrid" && allow_remote)) {
        auto info = CGBDataLoader::RegisterInObjectManager(
            *object_manager, CGBLoaderParams(), CObjectManager::eNonDefault, 2);
        scope->AddDataLoader(info.GetLoader()->GetName(), 2);
    }

    bool had_error = false;
    bool had_mismatch = false;
    const int warmup = args["warmup"].AsInteger();
    const int repeat = args["repeat"].AsInteger();
    for (int cycle = -warmup; cycle < repeat; ++cycle) {
        const bool report = cycle >= 0;
        for (const SRequest& request : requests) {
            const auto started = chrono::steady_clock::now();
            try {
                CSeq_id id(request.accession);
                CSeq_id_Handle idh = CSeq_id_Handle::GetHandle(id);
                CBioseq_Handle handle = scope->GetBioseqHandle(idh);
                if (!handle) throw runtime_error("accession was not resolved");
                const TSeqPos sequence_length = handle.GetBioseqLength();
                if (request.end > sequence_length) throw runtime_error("end exceeds sequence length");
                string observed;
                handle.GetSeqVector(CBioseq_Handle::eCoding_Iupac)
                    .GetSeqData(request.start, request.end, observed);
                observed = Upper(observed);
                const bool match = request.expected_ref.empty() || observed == request.expected_ref;
                had_mismatch = had_mismatch || !match;
                const auto elapsed = chrono::duration_cast<chrono::microseconds>(
                    chrono::steady_clock::now() - started).count();
                if (report) {
                    *output << "{\"request_id\":\"" << JsonEscape(request.request_id)
                            << "\",\"mode\":\"" << mode
                            << "\",\"accession\":\"" << JsonEscape(request.accession)
                            << "\",\"start\":" << request.start
                            << ",\"end\":" << request.end
                            << ",\"length\":" << (request.end - request.start)
                            << ",\"expected_ref\":\"" << JsonEscape(request.expected_ref)
                            << "\",\"observed_ref\":\""
                            << JsonEscape(print_sequence ? observed : observed)
                            << "\",\"match\":" << (match ? "true" : "false")
                            << ",\"elapsed_us\":" << elapsed
                            << ",\"iteration\":" << (cycle + 1)
                            << ",\"sequence_length\":" << sequence_length
                            << ",\"aliases\":" << AliasesJson(*scope, idh) << "}\n";
                }
            } catch (const exception& error) {
                had_error = true;
                const auto elapsed = chrono::duration_cast<chrono::microseconds>(
                    chrono::steady_clock::now() - started).count();
                if (report) {
                    *output << "{\"request_id\":\"" << JsonEscape(request.request_id)
                            << "\",\"mode\":\"" << mode
                            << "\",\"accession\":\"" << JsonEscape(request.accession)
                            << "\",\"start\":" << request.start
                            << ",\"end\":" << request.end
                            << ",\"iteration\":" << (cycle + 1)
                            << ",\"elapsed_us\":" << elapsed
                            << ",\"error_type\":\"retrieval_error\",\"error_message\":\""
                            << JsonEscape(error.what()) << "\"}\n";
                }
            }
        }
    }
    output->flush();
    return had_error || (fail_on_mismatch && had_mismatch) ? 1 : 0;
}

int main(int argc, const char* argv[])
{
    return CGksNcbiSequenceProbe().AppMain(argc, argv);
}
