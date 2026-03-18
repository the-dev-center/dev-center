/// VCS provider profiles loader. Reads org profile config from profiles.json5.
module modules.vcs.vcs_profiles;

import std.file : exists, readText;
import std.path : buildPath;
import std.string : replace;
import std.algorithm : endsWith;
import std.json : parseJSON, JSONValue, JSONType;

/// Org profile configuration for providers that support organization-level profile READMEs.
struct OrgProfileConfig
{
    string publicRepo;
    string privateRepo;  /// Empty if not supported (e.g. GitLab has only one).
    string readmePath;
    string readmeFormat;
    string baseUrl;
    string publicViewParam;
    string memberViewParam;
}

/// Full provider profile.
struct VCSProviderProfile
{
    string displayName;
    string hostPattern;
    OrgProfileConfig orgProfile;  /// Use orgProfile.publicRepo.length > 0 to check if supported.
}

/// Load provider profiles from profiles.json5. Returns null on failure.
JSONValue loadProfilesJson(string profilesPath)
{
    if (!exists(profilesPath)) return JSONValue.init;
    try
    {
        return parseJSON(readText(profilesPath));
    }
    catch (Exception)
    {
        return JSONValue.init;
    }
}

/// Parse orgProfile section from a provider's JSON object.
OrgProfileConfig parseOrgProfile(JSONValue provider)
{
    OrgProfileConfig c;
    auto op = provider["orgProfile"];
    if (op.type != JSONType.object)
        return c;

    auto s = (JSONValue v) { return (v.type == JSONType.string) ? v.str : ""; };
    c.publicRepo = s(op["publicRepo"]);
    c.privateRepo = s(op["privateRepo"]);
    c.readmePath = s(op["readmePath"]);
    c.readmeFormat = s(op["readmeFormat"]);
    c.baseUrl = s(op["baseUrl"]);
    c.publicViewParam = s(op["publicViewParam"]);
    c.memberViewParam = s(op["memberViewParam"]);
    return c;
}

/// Get provider profile for a host. Matches hostPattern (e.g. "github.com").
VCSProviderProfile getProviderForHost(JSONValue profiles, string host)
{
    VCSProviderProfile p;
    if (profiles.type != JSONType.object) return p;

    foreach (key, val; profiles.object)
    {
        auto hp = val["hostPattern"];
        if (hp.type == JSONType.string && hp.str == host)
        {
            p.displayName = val["displayName"].str;
            p.hostPattern = hp.str;
            p.orgProfile = parseOrgProfile(val);
            return p;
        }
    }
    return p;
}

/// Check if provider supports organization profiles.
bool hasOrgProfileSupport(VCSProviderProfile p)
{
    return p.orgProfile.publicRepo.length > 0;
}

/// Build public profile page URL for an org.
string orgProfilePublicUrl(VCSProviderProfile p, string org)
{
    if (!hasOrgProfileSupport(p)) return "";
    string url = p.orgProfile.baseUrl.replace("{org}", org).replace("{host}", p.hostPattern);
    if (p.orgProfile.publicViewParam.length > 0)
        url ~= p.orgProfile.publicViewParam;
    return url;
}

/// Build member/private profile page URL for an org.
string orgProfileMemberUrl(VCSProviderProfile p, string org)
{
    if (!hasOrgProfileSupport(p)) return "";
    string url = p.orgProfile.baseUrl.replace("{org}", org).replace("{host}", p.hostPattern);
    if (p.orgProfile.memberViewParam.length > 0)
        url ~= p.orgProfile.memberViewParam;
    return url;
}

/// Build repo URL for public profile repo (e.g. org/.github).
string orgProfilePublicRepoUrl(VCSProviderProfile p, string org)
{
    if (!hasOrgProfileSupport(p)) return "";
    string base = p.orgProfile.baseUrl.replace("{org}", org).replace("{host}", p.hostPattern);
    if (base.endsWith("/")) return base ~ p.orgProfile.publicRepo;
    return base ~ "/" ~ p.orgProfile.publicRepo;
}

/// Build repo URL for private profile repo (e.g. org/.github-private).
string orgProfilePrivateRepoUrl(VCSProviderProfile p, string org)
{
    if (!hasOrgProfileSupport(p) || p.orgProfile.privateRepo.length == 0) return "";
    string base = p.orgProfile.baseUrl.replace("{org}", org).replace("{host}", p.hostPattern);
    if (base.endsWith("/")) return base ~ p.orgProfile.privateRepo;
    return base ~ "/" ~ p.orgProfile.privateRepo;
}
