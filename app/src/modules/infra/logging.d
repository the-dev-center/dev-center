module modules.infra.logging;

import std.file : mkdirRecurse;
import std.logger : FileLogger, LogLevel, sharedLog, globalLogLevel, info, warning, error;
import std.path : buildPath;

private bool _initialized;
private string _logPath;

void initDevCenterLogging(string dataRoot)
{
    if (_initialized)
        return;
    auto logsDir = buildPath(dataRoot, "logs");
    mkdirRecurse(logsDir);
    _logPath = buildPath(logsDir, "dev-center.log");
    sharedLog = new shared FileLogger(_logPath);
    globalLogLevel = LogLevel.trace;
    _initialized = true;
    info("DevCentr logging initialized: ", _logPath);
}

string currentLogPath()
{
    return _logPath;
}

void logInfo(string message)
{
    if (_initialized)
        info(message);
}

void logWarning(string message)
{
    if (_initialized)
        warning(message);
}

void logError(string message)
{
    if (_initialized)
        error(message);
}
