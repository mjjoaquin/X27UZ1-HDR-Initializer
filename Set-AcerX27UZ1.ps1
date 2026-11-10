[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [ValidateRange(0, 100)]
    [int]$Brightness = 60
)

if ($Brightness -eq 0) {
    Write-Output 'Brightness 0 requested; no display changes made.'
    return
}

$acerWidgetPath = Join-Path $env:ProgramFiles 'Acer\Acer Display Widget'
if (-not (Test-Path (Join-Path $acerWidgetPath 'Monitor_MCCS_API_x64.dll'))) {
    throw "Acer Display Widget's native MCCS API was not found at $acerWidgetPath."
}
if (-not [Environment]::Is64BitProcess) {
    throw 'Run this script with 64-bit Windows PowerShell to load Acer''s x64 MCCS API.'
}

if (-not ('AcerX27UZ1.AcerMccs' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace AcerX27UZ1
{
    public static class AcerMccs
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct Rect
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct MonitorInfoEx
        {
            public int Size;
            public Rect Monitor;
            public Rect Work;
            public uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string DeviceName;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        public struct PhysicalMonitor
        {
            public IntPtr Handle;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string Description;
        }

        public struct MonitorTarget
        {
            public string DeviceName;
            public string Description;
            public IntPtr Handle;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct Luid
        {
            public uint LowPart;
            public int HighPart;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct TargetInfo
        {
            public uint Version;
            public Luid AdapterId;
            public uint TargetId;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 128)]
            public uint[] DisplayIds;
            public uint DisplayIdCount;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)]
            public uint[] Reserved;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DisplayIdInfo
        {
            public uint Version;
            public Luid AdapterId;
            public uint TargetId;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)]
            public uint[] Reserved;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct I2cInfo
        {
            public uint Version;
            public uint DisplayMask;
            public byte IsDdcPort;
            public byte DeviceAddress;
            public IntPtr RegisterAddress;
            public uint RegisterAddressSize;
            public IntPtr Data;
            public uint DataSize;
            public uint Speed;
            public int SpeedKhz;
            public byte PortId;
            public uint IsPortIdSet;
        }

        public delegate bool MonitorEnumProc(IntPtr monitor, IntPtr hdc, IntPtr rect, IntPtr data);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int NvApiInitializeDelegate();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int NvApiUnloadDelegate();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int GetDisplayIdByNameDelegate([MarshalAs(UnmanagedType.LPStr)] string name, out uint displayId);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int GetDisplayIdInfoDelegate(uint displayId, ref DisplayIdInfo info);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int GetDisplayIdsFromTargetDelegate(ref TargetInfo info);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int GetGpuAndOutputIdDelegate(uint displayId, out IntPtr gpu, out uint outputId);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int I2cTransferDelegate(IntPtr gpu, ref I2cInfo info);

        [DllImport("nvapi64.dll", EntryPoint = "nvapi_QueryInterface", CallingConvention = CallingConvention.Cdecl)]
        private static extern IntPtr NvApiQueryInterface(uint id);

        [DllImport("user32.dll")]
        private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc callback, IntPtr data);

        [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW", CharSet = CharSet.Unicode)]
        private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfoEx info);

        [DllImport("dxva2.dll", SetLastError = true)]
        private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr monitor, out uint count);

        [DllImport("dxva2.dll", SetLastError = true)]
        private static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr monitor, uint count, [Out] PhysicalMonitor[] physicalMonitors);

        [DllImport("dxva2.dll", SetLastError = true)]
        public static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr monitor, byte code, out byte type, out uint current, out uint maximum);

        [DllImport("dxva2.dll", SetLastError = true)]
        public static extern bool SetVCPFeature(IntPtr monitor, byte code, uint value);

        [DllImport("dxva2.dll", SetLastError = true)]
        public static extern bool DestroyPhysicalMonitor(IntPtr monitor);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool SetDllDirectory(string path);

        private static List<MonitorTarget> targets;

        private static bool EnumerateCallback(IntPtr monitor, IntPtr hdc, IntPtr rect, IntPtr data)
        {
            var info = new MonitorInfoEx();
            info.Size = Marshal.SizeOf(typeof(MonitorInfoEx));
            uint count;
            if (GetMonitorInfo(monitor, ref info) && GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, out count) && count > 0)
            {
                var physicalMonitors = new PhysicalMonitor[count];
                if (GetPhysicalMonitorsFromHMONITOR(monitor, count, physicalMonitors))
                {
                    foreach (var physical in physicalMonitors)
                    {
                        targets.Add(new MonitorTarget { DeviceName = info.DeviceName, Description = physical.Description, Handle = physical.Handle });
                    }
                }
            }
            return true;
        }

        public static MonitorTarget[] Enumerate()
        {
            targets = new List<MonitorTarget>();
            EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, EnumerateCallback, IntPtr.Zero);
            return targets.ToArray();
        }

        private static T GetNvApiFunction<T>(uint id) where T : class
        {
            IntPtr address = NvApiQueryInterface(id);
            if (address == IntPtr.Zero)
                throw new InvalidOperationException("NVAPI interface is unavailable: 0x" + id.ToString("X8"));
            return Marshal.GetDelegateForFunctionPointer(address, typeof(T)) as T;
        }

        private static uint NvApiVersion(Type type, uint version)
        {
            return ((uint)Marshal.SizeOf(type) & 0xffff) | (version << 16);
        }

        private static int I2cTransfer(I2cTransferDelegate transfer, IntPtr gpu, uint displayMask, byte address, byte[] bytes, byte[] registerAddress)
        {
            IntPtr dataBuffer = Marshal.AllocHGlobal(bytes.Length);
            IntPtr registerBuffer = IntPtr.Zero;
            try
            {
                Marshal.Copy(bytes, 0, dataBuffer, bytes.Length);
                if (registerAddress != null && registerAddress.Length > 0)
                {
                    registerBuffer = Marshal.AllocHGlobal(registerAddress.Length);
                    Marshal.Copy(registerAddress, 0, registerBuffer, registerAddress.Length);
                }

                var info = new I2cInfo {
                    Version = NvApiVersion(typeof(I2cInfo), 3),
                    DisplayMask = displayMask,
                    IsDdcPort = 1,
                    DeviceAddress = address,
                    RegisterAddress = registerBuffer,
                    RegisterAddressSize = registerAddress == null ? 0u : (uint)registerAddress.Length,
                    Data = dataBuffer,
                    DataSize = (uint)bytes.Length,
                    Speed = 0xffff,
                    SpeedKhz = 0,
                    PortId = 0,
                    IsPortIdSet = 0
                };

                int status = transfer(gpu, ref info);
                Marshal.Copy(dataBuffer, bytes, 0, bytes.Length);
                return status;
            }
            finally
            {
                Marshal.FreeHGlobal(dataBuffer);
                if (registerBuffer != IntPtr.Zero)
                    Marshal.FreeHGlobal(registerBuffer);
            }
        }

        private static uint ReadVcpValue(IntPtr gpu, uint outputId, byte vcpCode, I2cTransferDelegate write, I2cTransferDelegate read)
        {
            byte[] request = { 0x82, 0x01, vcpCode, 0x00 };
            byte checksum = 0x6e;
            checksum ^= 0x51;
            for (int i = 0; i < 3; i++)
                checksum ^= request[i];
            request[3] = checksum;

            int status = I2cTransfer(write, gpu, outputId, 0x6e, request, new byte[] { 0x51 });
            if (status != 0)
                throw new InvalidOperationException("NVAPI brightness request failed (status " + status + ").");

            System.Threading.Thread.Sleep(100);
            byte[] response = new byte[11];
            status = I2cTransfer(read, gpu, outputId, 0x6f, response, new byte[] { 0x6e });
            if (status != 0)
                throw new InvalidOperationException("NVAPI VCP 0x" + vcpCode.ToString("X2") + " reply failed (status " + status + ").");
            if (response[2] != 0x02 || response[3] != 0 || response[4] != vcpCode)
                throw new InvalidOperationException("NVAPI returned an invalid DDC/CI reply for VCP 0x" + vcpCode.ToString("X2") + ".");

            return (uint)((response[8] << 8) | response[9]);
        }

        private static void WriteVcpValue(IntPtr gpu, uint outputId, byte vcpCode, uint value, I2cTransferDelegate write)
        {
            byte[] request = { 0x84, 0x03, vcpCode, (byte)(value >> 8), (byte)value, 0x00 };
            byte checksum = 0x6e;
            checksum ^= 0x51;
            for (int i = 0; i < 5; i++)
                checksum ^= request[i];
            request[5] = checksum;

            int status = I2cTransfer(write, gpu, outputId, 0x6e, request, new byte[] { 0x51 });
            if (status != 0)
                throw new InvalidOperationException("NVAPI VCP 0x" + vcpCode.ToString("X2") + " write failed (status " + status + ").");
            System.Threading.Thread.Sleep(100);
        }

        public static uint SetSurroundSettings(string deviceName, uint brightness)
        {
            if (!System.IO.File.Exists(System.IO.Path.Combine(Environment.SystemDirectory, "nvapi64.dll")))
                return 1;

            NvApiInitializeDelegate initialize;
            NvApiUnloadDelegate unload;
            GetDisplayIdByNameDelegate getDisplayId;
            GetDisplayIdInfoDelegate getDisplayIdInfo;
            GetDisplayIdsFromTargetDelegate getDisplayIdsFromTarget;
            GetGpuAndOutputIdDelegate getGpuAndOutputId;
            I2cTransferDelegate i2cRead;
            I2cTransferDelegate i2cWrite;
            try
            {
                initialize = GetNvApiFunction<NvApiInitializeDelegate>(0x0150e828);
                unload = GetNvApiFunction<NvApiUnloadDelegate>(0xd22bdd7e);
                getDisplayId = GetNvApiFunction<GetDisplayIdByNameDelegate>(0xae457190);
                getDisplayIdInfo = GetNvApiFunction<GetDisplayIdInfoDelegate>(0xbae8aa5e);
                getDisplayIdsFromTarget = GetNvApiFunction<GetDisplayIdsFromTargetDelegate>(0xe7e5f89e);
                getGpuAndOutputId = GetNvApiFunction<GetGpuAndOutputIdDelegate>(0x112ba1a5);
                i2cRead = GetNvApiFunction<I2cTransferDelegate>(0x2fde12c5);
                i2cWrite = GetNvApiFunction<I2cTransferDelegate>(0xe812eb07);
            }
            catch (DllNotFoundException)
            {
                return 1;
            }
            catch (EntryPointNotFoundException)
            {
                return 1;
            }

            int status = initialize();
            if (status != 0)
                return 1;

            try
            {
                uint primaryId;
                status = getDisplayId(deviceName, out primaryId);
                if (status != 0)
                    return 1;

                var displayInfo = new DisplayIdInfo {
                    Version = NvApiVersion(typeof(DisplayIdInfo), 1),
                    Reserved = new uint[4]
                };
                status = getDisplayIdInfo(primaryId, ref displayInfo);
                if (status != 0)
                    return 1;

                var target = new TargetInfo {
                    Version = NvApiVersion(typeof(TargetInfo), 1),
                    AdapterId = displayInfo.AdapterId,
                    TargetId = displayInfo.TargetId,
                    DisplayIds = new uint[128],
                    DisplayIdCount = 128,
                    Reserved = new uint[4]
                };
                status = getDisplayIdsFromTarget(ref target);
                if (status != 0)
                    throw new InvalidOperationException("NVAPI Surround member enumeration failed (status " + status + ").");
                if (target.DisplayIdCount <= 1)
                    return 1;

                var targets = new List<SurroundTarget>();
                var outputMasks = new System.Collections.Generic.HashSet<uint>();
                for (int i = 0; i < target.DisplayIdCount; i++)
                {
                    IntPtr gpu;
                    uint outputId;
                    status = getGpuAndOutputId(target.DisplayIds[i], out gpu, out outputId);
                    if (status != 0 || gpu == IntPtr.Zero || outputId == 0)
                        throw new InvalidOperationException("Could not map Surround member 0x" + target.DisplayIds[i].ToString("X8") + " to a GPU output.");
                    if (!outputMasks.Add(outputId))
                        throw new InvalidOperationException("NVAPI returned a duplicate output mask for the Surround grid.");
                    targets.Add(new SurroundTarget { Gpu = gpu, OutputId = outputId });
                }

                foreach (var targetOutput in targets)
                {
                    WriteVcpValue(targetOutput.Gpu, targetOutput.OutputId, 0xe2, 11, i2cWrite);
                    System.Threading.Thread.Sleep(250);
                    uint refreshedMode = ReadVcpValue(targetOutput.Gpu, targetOutput.OutputId, 0xe2, i2cWrite, i2cRead);
                    if (refreshedMode != 11)
                        throw new InvalidOperationException("HDR mode verification failed for output mask 0x" + targetOutput.OutputId.ToString("X8") + " (read " + refreshedMode + ").");

                    WriteVcpValue(targetOutput.Gpu, targetOutput.OutputId, 0x10, brightness, i2cWrite);
                    System.Threading.Thread.Sleep(250);

                    uint mode = ReadVcpValue(targetOutput.Gpu, targetOutput.OutputId, 0xe2, i2cWrite, i2cRead);
                    if (mode != 0)
                        throw new InvalidOperationException("Expected final Acer User mode 0 for output mask 0x" + targetOutput.OutputId.ToString("X8") + ", but VCP 0xE2 read " + mode + ".");
                    uint actual = ReadVcpValue(targetOutput.Gpu, targetOutput.OutputId, 0x10, i2cWrite, i2cRead);
                    if (actual != brightness)
                        throw new InvalidOperationException("Brightness verification failed for output mask 0x" + targetOutput.OutputId.ToString("X8") + " (read " + actual + ").");
                }
                return (uint)targets.Count;
            }
            finally
            {
                unload();
            }
        }

        private struct SurroundTarget
        {
            public IntPtr Gpu;
            public uint OutputId;
        }
    }
}
'@
}

if (-not [AcerX27UZ1.AcerMccs]::SetDllDirectory($acerWidgetPath)) {
    throw "Could not add $acerWidgetPath to the native DLL search path."
}

# Reuse Acer's own P/Invoke declarations; a duplicate import did not initialize its MCCS state correctly.
$widgetAssembly = [Reflection.Assembly]::LoadFile((Join-Path $acerWidgetPath 'AcerDisplayWidget.exe'))
try {
    $widgetTypes = $widgetAssembly.GetTypes()
}
catch {
    $widgetTypes = @($_.Exception.InnerException.Types | Where-Object { $null -ne $_ })
}
$nativeApi = $widgetTypes | Where-Object { $_.FullName -eq 'AcerDisplayWidget.Acer_Class.AcerMCCS_API' }
if (-not $nativeApi) {
    throw 'Could not load Acer Display Widget''s MCCS API declarations.'
}
$bindingFlags = [Reflection.BindingFlags]'Public,NonPublic,Static,Instance,DeclaredOnly'
$initialize = $nativeApi.GetMethod('init_MCCS', $bindingFlags)
$getDisplayMode = $nativeApi.GetMethod('Monitor_GET_DisplayMode', $bindingFlags)
$setDisplayMode = $nativeApi.GetMethod('Monitor_Set_DisplayMode', $bindingFlags)
$setBrightness = $nativeApi.GetMethod('Monitor_SET_Brightness', $bindingFlags)
$freeNativeMonitor = $nativeApi.GetMethod('FreePhysicalMonitor', $bindingFlags)
if (-not $initialize -or -not $getDisplayMode -or -not $setDisplayMode -or -not $setBrightness -or -not $freeNativeMonitor) {
    throw 'A required Acer MCCS API method is missing.'
}

$targets = @([AcerX27UZ1.AcerMccs]::Enumerate() | Where-Object { $_.Description -eq 'Acer X27U Z1' })
if ($targets.Count -eq 0) {
    throw 'No Acer X27U Z1 monitors were found through Windows display enumeration.'
}

$failures = [System.Collections.Generic.List[string]]::new()
foreach ($monitor in $targets) {
    $label = "$($monitor.Description) $($monitor.DeviceName)"
    $initialized = $false
    try {
        # Acer expects DISPLAYn's zero-based selector index; Windows monitor enumeration order can differ.
        if ($monitor.DeviceName -notmatch '^\\\\\.\\DISPLAY(?<Number>\d+)$') {
            throw "Could not determine Acer's selector index for $($monitor.DeviceName)."
        }
        $selectorIndex = [int]$matches.Number - 1
        $initArgs = [object[]]@([int]$selectorIndex, [string]$monitor.DeviceName, [int]0, [int]0)
        if (-not $initialize.Invoke($null, $initArgs)) {
            throw "Acer MCCS initialization failed for $($monitor.DeviceName)."
        }
        $initialized = $true

        $modeArgs = [object[]]@([uint32]0, [uint32]0)
        if (-not $getDisplayMode.Invoke($null, $modeArgs)) {
            throw "Acer's display-mode getter failed for $($monitor.DeviceName)."
        }
        [uint32]$mode = $modeArgs[0]
        [uint32]$modeMaximum = $modeArgs[1]

        [byte]$type = 0
        [uint32]$currentBrightness = 0
        [uint32]$brightnessMaximum = 0
        if (-not [AcerX27UZ1.AcerMccs]::GetVCPFeatureAndVCPFeatureReply($monitor.Handle, 0x10, [ref]$type, [ref]$currentBrightness, [ref]$brightnessMaximum)) {
            throw "Cannot read brightness for $($monitor.DeviceName)."
        }

        Write-Output ("{0}: Acer mode {1}, brightness {2}/{3}." -f $label, $mode, $currentBrightness, $brightnessMaximum)

        # Acer's native mode API is authoritative: raw VCP 0x14 read 0x0B even when this API reported User mode 0.
        # After restart, mode 0 and the target brightness can still leave the video path in stale SDR; a manual preset change refreshed it.
        # Therefore always resend HDR mode 11, even if the reported values already match, then always reapply brightness.
        # Brightness switches the Acer preset back to User mode 0 while Windows Advanced Color remains enabled.
        # Do not send mode 11 again after brightness; that resets brightness to 100 and disrupts the working signal state.
        if ($PSCmdlet.ShouldProcess($label, "Refresh HDR mode, then set User-mode brightness to $Brightness")) {
            $surroundDisplayCount = [AcerX27UZ1.AcerMccs]::SetSurroundSettings($monitor.DeviceName, [uint32]$Brightness)
            if ($surroundDisplayCount -le 1) {
                if (-not $setDisplayMode.Invoke($null, [object[]]@([uint32]11))) {
                    throw "Acer's HDR mode command failed for $($monitor.DeviceName)."
                }
                # Match Acer's mode-settle delay before sending its brightness command.
                [System.Threading.Thread]::Sleep(250)
                if (-not $setBrightness.Invoke($null, [object[]]@([uint32]$Brightness))) {
                    throw "Acer's brightness command failed for $($monitor.DeviceName)."
                }
            }
            else {
                Write-Output ("{0}: refreshed Acer HDR mode then verified User mode 0 and brightness {1} on {2} NVIDIA Surround members." -f $label, $Brightness, $surroundDisplayCount)
            }
            [System.Threading.Thread]::Sleep(250)
        }

        if (-not $WhatIfPreference) {
            [void]$freeNativeMonitor.Invoke($null, [object[]]@())
            $initialized = $false
            $initArgs = [object[]]@([int]$selectorIndex, [string]$monitor.DeviceName, [int]0, [int]0)
            if (-not $initialize.Invoke($null, $initArgs)) {
                throw "Could not reconnect to $($monitor.DeviceName) to verify final settings."
            }
            $initialized = $true

            $modeArgs = [object[]]@([uint32]0, [uint32]0)
            if (-not $getDisplayMode.Invoke($null, $modeArgs) -or [uint32]$modeArgs[0] -ne 0) {
                $verifiedMode = [uint32]$modeArgs[0]
                throw "Expected final User mode 0 on $($monitor.DeviceName), but Acer reported mode $verifiedMode."
            }
            [uint32]$verifiedMode = $modeArgs[0]

            [uint32]$verifiedBrightness = 0
            [uint32]$unusedMaximum = 0
            if (-not [AcerX27UZ1.AcerMccs]::GetVCPFeatureAndVCPFeatureReply($monitor.Handle, 0x10, [ref]$type, [ref]$verifiedBrightness, [ref]$unusedMaximum)) {
                throw "Could not re-read brightness on $($monitor.DeviceName)."
            }
            if ($verifiedBrightness -ne $Brightness) {
                throw "Brightness verification failed on $($monitor.DeviceName) (read $verifiedBrightness)."
            }

            Write-Output ("{0}: verified final User mode {1} and brightness {2}." -f $label, $verifiedMode, $verifiedBrightness)
        }
    }
    catch {
        $failures.Add("${label}: $($_.Exception.Message)")
    }
    finally {
        if ($initialized) {
            [void]$freeNativeMonitor.Invoke($null, [object[]]@())
        }
        [void][AcerX27UZ1.AcerMccs]::DestroyPhysicalMonitor($monitor.Handle)
    }
}

if ($failures.Count -gt 0) {
    throw ($failures -join [Environment]::NewLine)
}