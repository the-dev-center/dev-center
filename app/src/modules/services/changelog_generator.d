module modules.services.changelog_generator;

import std.stdio;
import std.process;
import std.array;
import std.string;
import std.conv : to;

import modules.services.ai_providers;

struct ChangelogProposal
{
    string rawDiff;
    string generatedAsciidoc;
    string providerUsed;
}

class ChangelogGenerator
{
    private IAIService aiService;
    
    this(IAIService aiService)
    {
        this.aiService = aiService;
    }
    
    /// Pulls git history, diffs against AI, and returns a verified changelog addition proposal
    ChangelogProposal generateProposedChangelog(string repoPath, int commitCount = 10)
    {
        ChangelogProposal proposal;
        proposal.providerUsed = "Unknown";
        
        try
        {
            auto execResult = execute(["git", "log", "-p", "-n", to!string(commitCount)], null, Config.none, size_t.max, repoPath);
            if (execResult.status != 0) {
                proposal.rawDiff = "Error retrieving git log.";
                return proposal;
            }
            proposal.rawDiff = execResult.output;
            
            string systemPrompt = "You are a senior technical writer. Review the following git log diffs. Write a comprehensive, high-level summary of the architectural changes formatted in Asciidoc. Use bullet points and group by feature. Ignore trivial typo fixes.";
            string userPrompt = proposal.rawDiff;
            
            if (aiService !is null) {
                proposal.generatedAsciidoc = aiService.generateText(systemPrompt, userPrompt);
                proposal.providerUsed = "Connected AI Provider"; // Will pull from actual config in prod
            } else {
                proposal.generatedAsciidoc = "Error: No AI service configured. Set an API key in the AI Providers settings.";
            }
            
        } 
        catch (Exception e) 
        {
            proposal.rawDiff = "Exception: " ~ e.msg;
            proposal.generatedAsciidoc = "";
        }
        
        return proposal;
    }
    
    // Stub to verify format or compare different prompts if multiple AI profiles are enabled.
    bool verifyChangelogFormat(string asciidocOutput)
    {
        return asciidocOutput.indexOf("==") >= 0 || asciidocOutput.indexOf("* ") >= 0;
    }
}
