<#
.SYNOPSIS
    Utility - Run a process as the currently logged-on user from SYSTEM context.
.DESCRIPTION
    Uses Win32 CreateProcessAsUser to launch a process in the interactive
    user's session. Works from SYSTEM context (Intune Remediations).
    No Scheduled Task needed - execution is immediate.

    Usage:
        . .\Run-AsCurrentUser.ps1
        Run-AsCurrentUser -Filepath "powershell.exe" -CmdLine "-WindowStyle Hidden -File C:\path\to\script.ps1"
.NOTES
    Context: SYSTEM only
    Based on WTSQueryUserToken + CreateProcessAsUserW Win32 APIs
#>

function Run-AsCurrentUser {
    param(
        [Parameter(Mandatory)][string]$Filepath,
        [string]$CmdLine,
        [bool]$Visible = $false,
        [int]$Wait = -1,
        [bool]$Elevated = $false
    )

$Source = @"
using Microsoft.Win32.SafeHandles;
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace RunAsUser
{
    internal class NativeHelpers
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct PROCESS_INFORMATION
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public int dwProcessId;
            public int dwThreadId;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct STARTUPINFO
        {
            public int cb;
            public String lpReserved;
            public String lpDesktop;
            public String lpTitle;
            public uint dwX;
            public uint dwY;
            public uint dwXSize;
            public uint dwYSize;
            public uint dwXCountChars;
            public uint dwYCountChars;
            public uint dwFillAttribute;
            public uint dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct WTS_SESSION_INFO
        {
            public readonly UInt32 SessionID;
            [MarshalAs(UnmanagedType.LPStr)]
            public readonly String pWinStationName;
            public readonly WTS_CONNECTSTATE_CLASS State;
        }
    }

    internal class NativeMethods
    {
        [DllImport("kernel32", SetLastError=true)]
        public static extern int WaitForSingleObject(IntPtr hHandle, int dwMilliseconds);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr hSnapshot);

        [DllImport("userenv.dll", SetLastError = true)]
        public static extern bool CreateEnvironmentBlock(ref IntPtr lpEnvironment, SafeHandle hToken, bool bInherit);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool CreateProcessAsUserW(
            SafeHandle hToken, String lpApplicationName, StringBuilder lpCommandLine,
            IntPtr lpProcessAttributes, IntPtr lpThreadAttributes, bool bInheritHandle,
            uint dwCreationFlags, IntPtr lpEnvironment, String lpCurrentDirectory,
            ref NativeHelpers.STARTUPINFO lpStartupInfo, out NativeHelpers.PROCESS_INFORMATION lpProcessInformation);

        [DllImport("userenv.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool DestroyEnvironmentBlock(IntPtr lpEnvironment);

        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern bool DuplicateTokenEx(
            SafeHandle ExistingTokenHandle, uint dwDesiredAccess, IntPtr lpThreadAttributes,
            SECURITY_IMPERSONATION_LEVEL ImpersonationLevel, TOKEN_TYPE TokenType,
            out SafeNativeHandle DuplicateTokenHandle);

        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern bool GetTokenInformation(
            SafeHandle TokenHandle, uint TokenInformationClass,
            SafeMemoryBuffer TokenInformation, int TokenInformationLength, out int ReturnLength);

        [DllImport("wtsapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool WTSEnumerateSessions(
            IntPtr hServer, int Reserved, int Version, ref IntPtr ppSessionInfo, ref int pCount);

        [DllImport("wtsapi32.dll")]
        public static extern void WTSFreeMemory(IntPtr pMemory);

        [DllImport("kernel32.dll")]
        public static extern uint WTSGetActiveConsoleSessionId();

        [DllImport("Wtsapi32.dll", SetLastError = true)]
        public static extern bool WTSQueryUserToken(uint SessionId, out SafeNativeHandle phToken);
    }

    internal class SafeMemoryBuffer : SafeHandleZeroOrMinusOneIsInvalid
    {
        public SafeMemoryBuffer(int cb) : base(true) { base.SetHandle(Marshal.AllocHGlobal(cb)); }
        public SafeMemoryBuffer(IntPtr handle) : base(true) { base.SetHandle(handle); }
        protected override bool ReleaseHandle() { Marshal.FreeHGlobal(handle); return true; }
    }

    internal class SafeNativeHandle : SafeHandleZeroOrMinusOneIsInvalid
    {
        public SafeNativeHandle() : base(true) { }
        public SafeNativeHandle(IntPtr handle) : base(true) { this.handle = handle; }
        protected override bool ReleaseHandle() { return NativeMethods.CloseHandle(handle); }
    }

    internal enum SECURITY_IMPERSONATION_LEVEL { SecurityAnonymous = 0, SecurityIdentification = 1, SecurityImpersonation = 2, SecurityDelegation = 3 }
    internal enum SW { SW_HIDE = 0, SW_SHOW = 5 }
    internal enum TokenElevationType { TokenElevationTypeDefault = 1, TokenElevationTypeFull, TokenElevationTypeLimited }
    internal enum TOKEN_TYPE { TokenPrimary = 1, TokenImpersonation = 2 }
    internal enum WTS_CONNECTSTATE_CLASS { WTSActive, WTSConnected, WTSConnectQuery, WTSShadow, WTSDisconnected, WTSIdle, WTSListen, WTSReset, WTSDown, WTSInit }

    public class Win32Exception : System.ComponentModel.Win32Exception
    {
        private string _msg;
        public Win32Exception(string message) : this(Marshal.GetLastWin32Error(), message) { }
        public Win32Exception(int errorCode, string message) : base(errorCode)
        {
            _msg = String.Format("{0} ({1}, Win32ErrorCode {2} - 0x{2:X8})", message, base.Message, errorCode);
        }
        public override string Message { get { return _msg; } }
        public static explicit operator Win32Exception(string message) { return new Win32Exception(message); }
    }

    public static class ProcessExtensions
    {
        private const int CREATE_UNICODE_ENVIRONMENT = 0x00000400;
        private const int CREATE_NO_WINDOW = 0x08000000;
        private const int CREATE_NEW_CONSOLE = 0x00000010;
        private const uint INVALID_SESSION_ID = 0xFFFFFFFF;
        private static readonly IntPtr WTS_CURRENT_SERVER_HANDLE = IntPtr.Zero;

        private static SafeNativeHandle GetSessionUserToken(bool elevated)
        {
            var activeSessionId = INVALID_SESSION_ID;
            var pSessionInfo = IntPtr.Zero;
            var sessionCount = 0;

            if (NativeMethods.WTSEnumerateSessions(WTS_CURRENT_SERVER_HANDLE, 0, 1, ref pSessionInfo, ref sessionCount))
            {
                try
                {
                    var arrayElementSize = Marshal.SizeOf(typeof(NativeHelpers.WTS_SESSION_INFO));
                    var current = pSessionInfo;
                    for (var i = 0; i < sessionCount; i++)
                    {
                        var si = (NativeHelpers.WTS_SESSION_INFO)Marshal.PtrToStructure(current, typeof(NativeHelpers.WTS_SESSION_INFO));
                        current = IntPtr.Add(current, arrayElementSize);
                        if (si.State == WTS_CONNECTSTATE_CLASS.WTSActive) { activeSessionId = si.SessionID; break; }
                    }
                }
                finally { NativeMethods.WTSFreeMemory(pSessionInfo); }
            }

            if (activeSessionId == INVALID_SESSION_ID)
                activeSessionId = NativeMethods.WTSGetActiveConsoleSessionId();

            SafeNativeHandle hImpersonationToken;
            if (!NativeMethods.WTSQueryUserToken(activeSessionId, out hImpersonationToken))
                throw new Win32Exception("WTSQueryUserToken failed to get access token.");

            using (hImpersonationToken)
            {
                TokenElevationType elevationType = GetTokenElevationType(hImpersonationToken);
                if (elevationType == TokenElevationType.TokenElevationTypeLimited && elevated == true)
                {
                    using (var linkedToken = GetTokenLinkedToken(hImpersonationToken))
                        return DuplicateTokenAsPrimary(linkedToken);
                }
                else
                    return DuplicateTokenAsPrimary(hImpersonationToken);
            }
        }

        public static int StartProcessAsCurrentUser(string appPath, string cmdLine = null, string workDir = null, bool visible = false, int wait = -1, bool elevated = true)
        {
            using (var hUserToken = GetSessionUserToken(elevated))
            {
                var startInfo = new NativeHelpers.STARTUPINFO();
                startInfo.cb = Marshal.SizeOf(startInfo);
                uint dwCreationFlags = CREATE_UNICODE_ENVIRONMENT | (uint)(visible ? CREATE_NEW_CONSOLE : CREATE_NO_WINDOW);
                startInfo.wShowWindow = (short)(visible ? SW.SW_SHOW : SW.SW_HIDE);

                IntPtr pEnv = IntPtr.Zero;
                if (!NativeMethods.CreateEnvironmentBlock(ref pEnv, hUserToken, false))
                    throw new Win32Exception("CreateEnvironmentBlock failed.");

                try
                {
                    StringBuilder commandLine = new StringBuilder(cmdLine);
                    var procInfo = new NativeHelpers.PROCESS_INFORMATION();

                    if (!NativeMethods.CreateProcessAsUserW(hUserToken, appPath, commandLine,
                        IntPtr.Zero, IntPtr.Zero, false, dwCreationFlags, pEnv, workDir,
                        ref startInfo, out procInfo))
                        throw new Win32Exception("CreateProcessAsUser failed.");

                    try
                    {
                        NativeMethods.WaitForSingleObject(procInfo.hProcess, wait);
                        return procInfo.dwProcessId;
                    }
                    finally
                    {
                        NativeMethods.CloseHandle(procInfo.hThread);
                        NativeMethods.CloseHandle(procInfo.hProcess);
                    }
                }
                finally { NativeMethods.DestroyEnvironmentBlock(pEnv); }
            }
        }

        private static SafeNativeHandle DuplicateTokenAsPrimary(SafeHandle hToken)
        {
            SafeNativeHandle pDupToken;
            if (!NativeMethods.DuplicateTokenEx(hToken, 0, IntPtr.Zero,
                SECURITY_IMPERSONATION_LEVEL.SecurityImpersonation, TOKEN_TYPE.TokenPrimary, out pDupToken))
                throw new Win32Exception("DuplicateTokenEx failed.");
            return pDupToken;
        }

        private static TokenElevationType GetTokenElevationType(SafeHandle hToken)
        {
            using (SafeMemoryBuffer tokenInfo = GetTokenInformation(hToken, 18))
                return (TokenElevationType)Marshal.ReadInt32(tokenInfo.DangerousGetHandle());
        }

        private static SafeNativeHandle GetTokenLinkedToken(SafeHandle hToken)
        {
            using (SafeMemoryBuffer tokenInfo = GetTokenInformation(hToken, 19))
                return new SafeNativeHandle(Marshal.ReadIntPtr(tokenInfo.DangerousGetHandle()));
        }

        private static SafeMemoryBuffer GetTokenInformation(SafeHandle hToken, uint infoClass)
        {
            int returnLength;
            bool res = NativeMethods.GetTokenInformation(hToken, infoClass, new SafeMemoryBuffer(IntPtr.Zero), 0, out returnLength);
            int errCode = Marshal.GetLastWin32Error();
            if (!res && errCode != 24 && errCode != 122)
                throw new Win32Exception(errCode, String.Format("GetTokenInformation({0}) failed to get buffer length", infoClass));

            SafeMemoryBuffer tokenInfo = new SafeMemoryBuffer(returnLength);
            if (!NativeMethods.GetTokenInformation(hToken, infoClass, tokenInfo, returnLength, out returnLength))
                throw new Win32Exception(String.Format("GetTokenInformation({0}) failed", infoClass));
            return tokenInfo;
        }
    }
}
"@

    try {
        Add-Type -ReferencedAssemblies 'System', 'System.Runtime.InteropServices' -TypeDefinition $Source -Language CSharp -ErrorAction Stop
    } catch {
        if ($_.Exception.Message -notmatch 'already exists') { throw $_ }
    }

    [RunAsUser.ProcessExtensions]::StartProcessAsCurrentUser($Filepath, $CmdLine, $null, $Visible, $Wait, $Elevated)
}
