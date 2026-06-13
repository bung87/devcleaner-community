## Discord Rich Presence integration
## Implements Discord IPC protocol for macOS using POSIX sockets

import std/[os, json, times, options]
import chronicles
import filesize

const
  DiscordClientID = "1479573788386394334"  # Application ID from Discord Developer Portal
  DiscordPartyID = "ae488379-351d-4a4f-ad32-2b9b01c91657"        # Party ID for Rich Presence buttons
  DiscordJoinSecret = "MTI4NzM0OjFpMmhuZToxMjMxMjM="    # Join secret for Rich Presence buttons

  AF_UNIX = 1
  SOCK_STREAM = 1
  IPPROTO_IP = 0

  MSG_NOSIGNAL = 0x8000'i32  # Don't raise SIGPIPE on errors

  F_GETFL = 3
  F_SETFL = 4
  O_NONBLOCK = 0x0004

  EAGAIN = 35
  EWOULDBLOCK = 35  # On macOS, EAGAIN == EWOULDBLOCK

type
  SockAddr_Un = object
    sun_family: uint16
    sun_path: array[108, char]

  DiscordButton* = object
    label*: string
    url*: string

  DiscordActivity* = ref object
    details*: string
    state*: string
    largeImageKey*: string
    largeImageText*: string
    smallImageKey*: string
    smallImageText*: string
    startTimestamp*: Option[int64]
    buttons*: seq[DiscordButton]
    partyId*: string
    partySize*: int
    partyMax*: int
    joinSecret*: string
    spectateSecret*: string

  DiscordCmd = enum
    dcConnect
    dcDisconnect
    dcSetActivity

  DiscordMessage = object
    cmd: DiscordCmd
    activity: DiscordActivity

  IPCSocket = object
    fd: cint

var
  gDiscordEnabled: bool = false
  gDiscordConnected: bool = false
  gActivityStartTime: Time = Time()
  gMessageChannel: Channel[DiscordMessage]
  gWorkerThread: Thread[void]
  gShouldStop: bool = false

proc socket(domain: cint, socktype: cint, protocol: cint): cint {.importc, header: "<sys/socket.h>".}
proc connect(sockfd: cint, addrPtr: pointer, addrlen: cuint): cint {.importc, header: "<sys/socket.h>".}
proc send(sockfd: cint, buf: pointer, len: csize_t, flags: cint): cint {.importc, header: "<sys/socket.h>".}
proc recv(sockfd: cint, buf: pointer, len: csize_t, flags: cint): cint {.importc, header: "<sys/socket.h>".}
proc close(fd: cint): cint {.importc, header: "<unistd.h>".}
proc fcntl(fd: cint, cmd: cint, arg: cint): cint {.importc, header: "<fcntl.h>".}
proc strerror(errnum: cint): cstring {.importc, header: "<string.h>".}
proc usleep(usec: cuint): cint {.importc, header: "<unistd.h>".}

var errno {.importc, header: "<errno.h>".}: cint

proc getDiscordIPCPath(): string =
  let tmpDir = getTempDir()
  for i in 0..9:
    let path = tmpDir & "discord-ipc-" & $i
    if fileExists(path):
      return path
  return tmpDir & "discord-ipc-0"

proc newIPCSocket(): IPCSocket =
  let fd = socket(AF_UNIX.cint, SOCK_STREAM.cint, IPPROTO_IP.cint)
  return IPCSocket(fd: fd)

proc isValid(sock: IPCSocket): bool = sock.fd >= 0

proc close(sock: IPCSocket) =
  if sock.fd >= 0:
    discard close(sock.fd)

proc setNonBlocking(sock: IPCSocket, nonBlocking: bool) =
  var flags = fcntl(sock.fd, F_GETFL, 0)
  if nonBlocking:
    flags = flags or O_NONBLOCK
  else:
    flags = flags and (not O_NONBLOCK)
  discard fcntl(sock.fd, F_SETFL, flags)

proc connectUnix(sock: IPCSocket; path: string): bool =
  var sockAddr: SockAddr_Un
  sockAddr.sun_family = AF_UNIX.uint16
  let pathLen = min(path.len, 107)
  copyMem(addr sockAddr.sun_path[0], path.cstring, pathLen)
  sockAddr.sun_path[pathLen] = '\0'

  let connResult = connect(sock.fd, addr sockAddr, sizeof(SockAddr_Un).cuint)
  return connResult == 0

proc sendAll(sock: IPCSocket; data: string): bool =
  var totalSent = 0
  while totalSent < data.len:
    let n = send(sock.fd, addr data[totalSent], (data.len - totalSent).csize_t, MSG_NOSIGNAL)
    if n < 0:
      let err = errno
      if err == EAGAIN or err == EWOULDBLOCK:
        discard usleep(1000)
        continue
      debug "Discord RPC send failed"
      return false
    elif n == 0:
      return false
    totalSent += n
  return true

proc readResponse(sock: IPCSocket; timeoutMs: int = 5000): string =
  ## Read response from Discord with timeout
  sock.setNonBlocking(true)
  let startTime = epochTime()
  var response = ""

  while (epochTime() - startTime) * 1000 < timeoutMs.float:
    if response.len < 8:
      var buf: array[8, char]
      let n = recv(sock.fd, addr buf[0], (8 - response.len).csize_t, 0)
      if n > 0:
        for i in 0..<n:
          response.add(buf[i])
      elif n < 0:
        let err = errno
        if err != EAGAIN and err != EWOULDBLOCK:
          debug "Discord RPC receive failed"
          sock.setNonBlocking(false)
          return ""
        discard usleep(1000)
      else:
        # Connection closed
        sock.setNonBlocking(false)
        return ""
    else:
      var msgLen: int32
      copyMem(addr msgLen, addr response[4], 4)

      if response.len < 8 + msgLen:
        let toRead = (8 + msgLen) - response.len
        var buf = newString(toRead)
        let n = recv(sock.fd, addr buf[0], toRead.csize_t, 0)
        if n > 0:
          response.add(buf[0..<n])
        elif n < 0:
          let err = errno
          if err != EAGAIN and err != EWOULDBLOCK:
            debug "Discord RPC receive failed"
            sock.setNonBlocking(false)
            return ""
          discard usleep(1000)
        else:
          sock.setNonBlocking(false)
          return ""
      else:
        sock.setNonBlocking(false)
        return response

  sock.setNonBlocking(false)
  return ""

proc sendIPC(sock: IPCSocket; opcode: int32; data: JsonNode): bool =
  if not sock.isValid:
    return false

  let payload = $data
  var header = newString(8)
  copyMem(addr header[0], addr opcode, 4)
  let len = payload.len.int32
  copyMem(addr header[4], addr len, 4)

  return sock.sendAll(header & payload)

proc tryConnect(): IPCSocket =
  debug "Discord RPC connecting"

  var sock = newIPCSocket()
  if not sock.isValid:
    debug "Discord RPC failed to create socket"
    return IPCSocket(fd: -1)

  debug "Discord RPC connecting to IPC"
  if not sock.connectUnix(getDiscordIPCPath()):
    debug "Discord RPC connection failed"
    sock.close()
    return IPCSocket(fd: -1)

  debug "Discord RPC connected, sending handshake"

  # Send handshake
  let data = %*{ "v": 1, "client_id": DiscordClientID }
  let payload = $data
  var header = newString(8)
  var opcode: int32 = 0
  copyMem(addr header[0], addr opcode, 4)
  let len = payload.len.int32
  copyMem(addr header[4], addr len, 4)

  if not sock.sendAll(header & payload):
    debug "Discord RPC handshake failed"
    sock.close()
    return IPCSocket(fd: -1)

  debug "Discord RPC handshake sent, waiting for response"

  # Read handshake response
  let response = sock.readResponse(5000)
  if response.len == 0:
    debug "Discord RPC no handshake response"
    sock.close()
    return IPCSocket(fd: -1)

  debug "Discord RPC handshake response received"

  # Parse and log the response
  if response.len > 8:
    var msgLen: int32
    copyMem(addr msgLen, addr response[4], 4)
    if response.len >= 8 + msgLen:
      let jsonStr = response[8..<(8+msgLen)]
      debug "Discord RPC handshake response parsed"
      # Check for error
      try:
        let jsonData = parseJson(jsonStr)
        if jsonData.hasKey("code"):
          let code = jsonData["code"].getInt
          if code != 0:
            debug "Discord RPC handshake error"
            sock.close()
            return IPCSocket(fd: -1)
      except:
        discard

  info "Discord Rich Presence connected"
  return sock

proc discordWorker() {.thread.} =
  ## Background thread for Discord IPC communication
  var socket = IPCSocket(fd: -1)

  debug "Discord RPC worker started"

  while not gShouldStop:
    let (available, msg) = gMessageChannel.tryRecv()
    if available:
      debug "Discord RPC received command"
      case msg.cmd
      of dcConnect:
        debug "Discord RPC connect requested"
        if not socket.isValid:
          debug "Discord RPC attempting to connect"
          socket = tryConnect()
          if socket.isValid:
            gDiscordConnected = true
            info "Discord Rich Presence connected"
            # Send initial idle status
            let idleActivity = DiscordActivity(
              details: "⏳ Idle",
              state: "Ready to scan"
            )
            var act = %*{}
            act["details"] = %idleActivity.details
            act["state"] = %idleActivity.state
            let data = %*{
              "cmd": "SET_ACTIVITY",
              "args": { "pid": getCurrentProcessId(), "activity": act },
              "nonce": $epochTime()
            }
            discard sendIPC(socket, 1, data)
          else:
            debug "Discord RPC connection failed"
            socket = IPCSocket(fd: -1)
        else:
          debug "Discord RPC already connected"
      of dcDisconnect:
        if socket.isValid:
          try:
            let data = %*{
              "cmd": "SET_ACTIVITY",
              "args": { "pid": getCurrentProcessId() },
              "nonce": $epochTime()
            }
            discard sendIPC(socket, 1, data)
            socket.close()
          except:
            discard
          socket = IPCSocket(fd: -1)
          gDiscordConnected = false
      of dcSetActivity:
        debug "Discord RPC setting activity"
        if socket.isValid:
          var act = %*{}
          if msg.activity.details.len > 0:
            act["details"] = %msg.activity.details
          if msg.activity.state.len > 0:
            act["state"] = %msg.activity.state

          var assets = %*{}
          if msg.activity.largeImageKey.len > 0:
            assets["large_image"] = %msg.activity.largeImageKey
            if msg.activity.largeImageText.len > 0:
              assets["large_text"] = %msg.activity.largeImageText
          if msg.activity.smallImageKey.len > 0:
            assets["small_image"] = %msg.activity.smallImageKey
            if msg.activity.smallImageText.len > 0:
              assets["small_text"] = %msg.activity.smallImageText

          if assets.len > 0:
            act["assets"] = assets

          if msg.activity.startTimestamp.isSome:
            act["timestamps"] = %*{ "start": msg.activity.startTimestamp.get }

          # Add party info for "Ask to Join" button
          if msg.activity.partyId.len > 0:
            act["party"] = %*{
              "id": msg.activity.partyId,
              "size": [msg.activity.partySize, msg.activity.partyMax]
            }
            if msg.activity.joinSecret.len > 0:
              act["secrets"] = %*{
                "join": msg.activity.joinSecret
              }

          let data = %*{
            "cmd": "SET_ACTIVITY",
            "args": { "pid": getCurrentProcessId(), "activity": act },
            "nonce": $epochTime()
          }
          debug "Discord RPC sending activity data"
          let success = sendIPC(socket, 1, data)
          if success:
            debug "Discord RPC activity sent successfully"
          else:
            debug "Discord RPC failed to send activity"
            socket.close()
            socket = IPCSocket(fd: -1)
            gDiscordConnected = false
        else:
          debug "Discord RPC cannot set activity: not connected"
    sleep(100)  # 100ms polling

  # Cleanup on exit
  if socket.isValid:
    socket.close()

proc connectDiscord*() =
  ## Request connection to Discord
  debug "Discord RPC connect requested"
  gMessageChannel.send(DiscordMessage(cmd: dcConnect))

proc disconnectDiscord*() =
  ## Request disconnection from Discord
  debug "Discord RPC disconnect requested"
  gMessageChannel.send(DiscordMessage(cmd: dcDisconnect))

proc setDiscordEnabled*(enabled: bool) =
  ## Enable/disable Discord integration
  info "Discord Rich Presence", status = (if enabled: "enabled" else: "disabled")
  gDiscordEnabled = enabled
  if enabled:
    connectDiscord()
  else:
    disconnectDiscord()

proc isDiscordEnabled*(): bool = gDiscordEnabled
proc isDiscordConnected*(): bool = gDiscordConnected

proc updateDiscordStatus*(scanning: bool = false; cleaning: bool = false; totalSize: int64 = 0; cleanedSize: int64 = 0; itemCount: int = 0; appName: string = "") =
  ## Update Discord status based on app state
  debug "Discord RPC updating status"
  if not gDiscordEnabled:
    return

  var activity = DiscordActivity()
  # Party info for "Ask to Join" button (like the official example)
  # activity.partyId = DiscordPartyID
  # activity.partySize = 1
  # activity.partyMax = 5
  # activity.joinSecret = DiscordJoinSecret

  if scanning:
    if appName.len > 0 and totalSize > 0:
      # Show current app being scanned with its size
      let sizeStr = fileSizeHumanReadable(totalSize)
      activity.details = "🔍 " & appName & " — Scanning artifacts..."
      activity.state = "Found " & $itemCount & " items (" & sizeStr & ")"
    else:
      activity.details = "🔍 Scanning for artifacts files..."
      activity.state = "Looking for development artifacts"
    if gActivityStartTime == Time():
      gActivityStartTime = now().toTime()
    activity.startTimestamp = some(gActivityStartTime.toUnix)
  elif cleaning:
    # Cleaning in progress
    let sizeStr = fileSizeHumanReadable(cleanedSize)
    if appName.len > 0:
      activity.details = "🧹 Cleaned " & appName
      activity.state = "Freed " & sizeStr
    else:
      activity.details = "🧹 Cleaning artifacts..."
      activity.state = "Freed " & sizeStr
    activity.startTimestamp = none(int64)
    gActivityStartTime = Time()
  elif totalSize > 0:
    let sizeStr = fileSizeHumanReadable(totalSize)
    activity.details = "🗑️ Found " & $itemCount & " items"
    activity.state = "Size: " & sizeStr
    activity.startTimestamp = none(int64)
    gActivityStartTime = Time()
  else:
    activity.details = "⏳ Idle"
    activity.state = "Ready to scan"
    activity.startTimestamp = none(int64)
    gActivityStartTime = Time()

  gMessageChannel.send(DiscordMessage(cmd: dcSetActivity, activity: activity))

proc initDiscordRPC*() =
  ## Initialize Discord RPC worker thread
  debug "Discord RPC initializing"
  gMessageChannel.open()
  createThread(gWorkerThread, discordWorker)
  debug "Discord RPC initialized"

proc shutdownDiscordRPC*() =
  ## Shutdown Discord RPC
  debug "Discord RPC shutting down"
  gShouldStop = true
  # Don't wait for thread - let it exit on its own
  # joinThread(gWorkerThread)
  gMessageChannel.close()
  debug "Discord RPC shutdown complete"
