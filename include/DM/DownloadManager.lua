local _ = [[---------- Usage ----------

1. Create a DownloadManager:

	manager = DownloadManager!

	You can supply a single library search path or a table of search paths for the DownloadManager library.
	On Aegisub, this will default to the system and user DownloadManager module directories.
	Otherwise the default library search path will be used.

2. Add some downloads:

	manager\addDownload "https://a.real.website", "out3"

	If you have a SHA-1 hash to check the downloaded file against, use:
		manager\addDownload "https://a.real.website", "out2", "b52854d1f79de5ebeebf0160447a09c7a8c2cde4"

	You may want to keep a reference of your download to check its result later:
		myDownload = manager\addDownload "https://a.real.website", "out2",

	Downloads will start immediately. Do whatever you want here while downloads happen in the background.
	The output file must contain a full path and file name. There is no working directory and automatic file naming is unsupported.

3. Wait for downloads to finish:

	Call manager\waitForFinish(cb) to loop until remaining downloads finish.
	The progress callback can call manager\cancel! or manager\clear! to interrupt and break open connections.

	The current overall progress will be passed to the provided callback as a number in range 0-100:
		manager\waitForFinish ( progress ) ->
			print tostring progress

4. Check for download errors:

	Check a specific download:
		error dl.error if dl.error

	Print all failed downloads:
		for dl in *manager.failedDownloads
			print "Download ##{dl.id} error: #{dl.error}"

	Get a descriptive overall error message:
		error = table.concat ["#{dl.url}: #{dl.error}" for dl in *manager.failedDownloads], "\n"

5. Clear all downloads:

	manager\clear!

	Removes all downloads from the downloader and resets all counters.


Error Handling:
	Errors are handled in typical Lua fashion.
	DownloadManager will only throw an error in case the library failed to load.
	Errors will also be thrown if the wrong type is passed in to certain functions to avoid
	missing incorrect usage.
	If any other error is encountered the script will return nil along with an error message.

]]
local havelfs, lfs = pcall(require, "lfs")
local ffi = require("ffi")
local requireffi = require("requireffi.requireffi")
ffi.cdef([[struct CDlM;
typedef struct CDlM CDlM;
typedef unsigned int uint;
 CDlM*       newDM        ( void );
 uint        addDownload  ( CDlM *mgr,           const char *url,
                                  const char *outfile, const char *sha1,
                                  char **etag );
 double      progress     ( CDlM *mgr );
 int         busy         ( CDlM *mgr );
 int         checkDownload( CDlM *mgr, uint i );
 const char* getError     ( CDlM *mgr, uint i );
 void        terminate    ( CDlM *mgr );
 void        clear        ( CDlM *mgr );
 const char* getFileSHA1  ( const char *filename );
 const char* getStringSHA1( const char *string );
 uint        version      ( void );
 void        freeDM       ( CDlM *mgr );
 _Bool        isInternetConnected( void );
int usleep(unsigned int);
void Sleep(unsigned long);
char *strdup(const char *);
char *_strdup(const char *);
]])
local DMVersion = 0x000300
local DM, loadedLibraryPath = requireffi("DM.DownloadManager.DownloadManager")
local libVer = DM.version()
if libVer < DMVersion or math.floor(libVer / 65536 % 256) > math.floor(DMVersion / 65536 % 256) then
  error("Library version mismatch. Wanted " .. tostring(DMVersion) .. ", got " .. tostring(libVer) .. ".")
end
local sleep = ffi.os == "Windows" and (function(ms)
  if ms == nil then
    ms = 100
  end
  return ffi.C.Sleep(ms)
end) or (function(ms)
  if ms == nil then
    ms = 100
  end
  return ffi.C.usleep(ms * 1000)
end)
local strdup = ffi.os == "Windows" and ffi.C._strdup or ffi.C.strdup
local DownloadManager
do
  local msgs, freeManager, sanitizeFile, getCachedFile, copyFile, etagCacheCheck
  local _base_0 = {
    loadedLibraryPath = loadedLibraryPath,
    addDownload = function(self, url, outfile, sha1, etag)
      if not (DM) then
        return nil, msgs.notInitialized
      end
      local urlType, outfileType = type(url), type(outfile)
      assert(urlType == "string" and outfileType == "string", msgs.addMissingArgs:format(urlType, outfileType))
      local msg
      outfile, msg = sanitizeFile(outfile)
      if outfile == nil then
        return outfile, msg
      end
      if "string" == type(sha1) then
        sha1 = sha1:lower()
      else
        sha1 = nil
      end
      local cEtag = ffi.new("char*[1]")
      if "string" == type(etag) then
        cEtag[0] = strdup(etag)
      else
        cEtag[0] = strdup("")
      end
      DM.addDownload(self.manager, url, outfile, sha1, cEtag)
      self.downloadCount = self.downloadCount + 1
      self.downloads[self.downloadCount] = {
        id = self.downloadCount,
        url = url,
        outfile = outfile,
        sha1 = sha1,
        etag = etag,
        cEtag = cEtag
      }
      return self.downloads[self.downloadCount]
    end,
    progress = function(self)
      if not (DM) then
        return nil, msgs.notInitialized
      end
      return math.floor(100 * DM.progress(self.manager))
    end,
    cancel = function(self)
      if not (DM) then
        return nil, msgs.notInitialized
      end
      return DM.terminate(self.manager)
    end,
    clear = function(self)
      if not (DM) then
        return nil, msgs.notInitialized
      end
      DM.clear(self.manager)
      self.downloads = { }
      self.failedDownloads = { }
      self.downloadCount = 0
      self.failedCount = 0
    end,
    waitForFinish = function(self, callback)
      if not (DM) then
        return nil, msgs.notInitialized
      end
      while 0 ~= DM.busy(self.manager) do
        if callback and not callback(self:progress()) then
          return 
        end
        sleep()
      end
      self.failedCount = 0
      for i = 1, self.downloadCount do
        local download = self.downloads[i]
        if download.cEtag ~= nil then
          if download.cEtag[0] ~= nil then
            download.newEtag = ffi.string(download.cEtag[0])
          end
          download.cEtag = nil
        end
        local err = DM.getError(self.manager, i)
        if err ~= nil then
          self.failedCount = self.failedCount + 1
          self.failedDownloads[self.failedCount] = download
          download.error = ffi.string(err)
          download.failed = true
        end
        if self.cacheDir and download.newEtag and not download.failed then
          local msg
          err, msg = pcall(etagCacheCheck, download, self)
          if not err then
            download.error = "Etag cache check failed with message: " .. msg
            download.failed = true
          end
        end
        if "function" == type(download.callback) then
          download:callback(self)
        end
      end
    end,
    checkFileSHA1 = function(self, filename, expected)
      local filenameType, expectedType = type(filename), type(expected)
      assert(filenameType == "string" and expectedType == "string", msgs.checkMissingArgs:format(filenameType, expectedType))
      local result = DM.getFileSHA1(filename)
      if nil == result then
        return nil, "Could not open file " .. tostring(filename) .. "."
      else
        result = ffi.string(result)
      end
      if result == expected:lower() then
        return true
      else
        return false, "Hash mismatch. Got " .. tostring(result) .. ", expected " .. tostring(expected) .. "."
      end
    end,
    checkStringSHA1 = function(self, string, expected)
      local stringType, expectedType = type(string), type(expected)
      assert(stringType == "string" and expectedType == "string", msgs.checkMissingArgs:format(stringType, expectedType))
      local result = ffi.string(DM.getStringSHA1(string))
      if result == expected:lower() then
        return true
      else
        return false, "Hash mismatch. Got " .. tostring(result) .. ", expected " .. tostring(expected) .. "."
      end
    end,
    isInternetConnected = function(self)
      return DM.isInternetConnected()
    end
  }
  _base_0.__index = _base_0
  local _class_0 = setmetatable({
    __init = function(self, etagCacheDir)
      self.manager = ffi.gc(DM.newDM(), freeManager)
      self.downloads = { }
      self.downloadCount = 0
      self.failedDownloads = { }
      self.failedCount = 0
      if etagCacheDir then
        local result, message = sanitizeFile(etagCacheDir:gsub("[/\\]*$", "/", 1), true)
        assert(message == nil, message)
        self.cacheDir = result
      end
    end,
    __base = _base_0,
    __name = "DownloadManager"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  local self = _class_0
  self.version = 0x000301
  self.version_string = "0.3.1"
  self.__depCtrlInit = function(DependencyControl)
    self.version = DependencyControl({
      name = tostring(self.__name),
      version = self.version_string,
      description = "Download things with libcurl without blocking Lua.",
      author = "torque",
      url = "https://github.com/torque/ffi-experiments",
      moduleName = "DM." .. tostring(self.__name),
      feed = "https://raw.githubusercontent.com/torque/ffi-experiments/master/DependencyControl.json"
    })
  end
  msgs = {
    notInitialized = tostring(self.__name) .. " not initialized.",
    addMissingArgs = "Required arguments #1 (url) or #2 (outfile) had the wrong type. Expected string, got '%s' and '%s'.",
    checkMissingArgs = "Required arguments #1 (filename/string) and #2 (expected) or the wrong type. Expected string, got '%s' and '%s'.",
    outNoFullPath = "Argument #2 (outfile) must contain a full path (relative paths not supported), got %s.",
    outNoFile = "Argument #2 (outfile) must contain a full path with file name, got %s."
  }
  freeManager = function(manager)
    return DM.freeDM(manager)
  end
  sanitizeFile = function(filename, acceptDir)
    do
      local homeDir = os.getenv("HOME")
      if homeDir then
        filename = filename:gsub("^~/", homeDir .. "/")
      end
    end
    local dev, dir, file = filename:match("^(" .. tostring(ffi.os == 'Windows' and '%a:[/\\]' or '/') .. ")(.*[/\\])(.*)$")
    if not dev or #dir < 1 then
      return nil, msgs.outNoFullPath:format(filename)
    elseif not acceptDir and #file < 1 then
      return nil, msgs.outNoFile:format(filename)
    end
    dir = dev .. dir
    if havelfs then
      local mode, err = lfs.attributes(dir, "mode")
      if mode ~= "directory" then
        if err then
          return nil, err
        end
        local res
        res, err = lfs.mkdir(dir)
        if err then
          return nil, err
        end
      end
    else
      os.execute("mkdir " .. tostring(ffi.os == 'Windows' and '' or '-p ') .. "\"" .. tostring(dir) .. "\"")
    end
    return dir .. file
  end
  getCachedFile = function(self, etag)
    return self.cacheDir .. etag
  end
  copyFile = function(source, target)
    local input, msg = io.open(source, 'rb')
    assert(input, msg)
    local output
    output, msg = io.open(target, 'wb')
    assert(output, msg)
    local err
    err, msg = output:write(input:read('*a'))
    assert(err, msg)
    input:close()
    return output:close()
  end
  etagCacheCheck = function(self, manager)
    local source = getCachedFile(manager, self.newEtag)
    if self.newEtag == self.etag then
      return copyFile(source, self.outfile)
    else
      return copyFile(self.outfile, source)
    end
  end
  DownloadManager = _class_0
  return _class_0
end
