// GDI screen capture cannot read hardware-composited window content (e.g. the WeChat login
// QR code) while the active output is a physical GPU output on some drivers. Activating a
// software indirect display forces a GDI-readable composition path, so whenever capture
// falls back to GDI we enable the bundled virtual display and capture through it.
use hbb_common::{bail, log, ResultType};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;
use winapi::shared::minwindef::FALSE;
use winapi::um::wingdi::{
    DEVMODEW, DISPLAY_DEVICEW, DISPLAY_DEVICE_ACTIVE, DISPLAY_DEVICE_PRIMARY_DEVICE,
    DM_BITSPERPEL, DM_DISPLAYFREQUENCY, DM_PELSHEIGHT, DM_PELSWIDTH, DM_POSITION,
};
use winapi::um::winuser::{
    ChangeDisplaySettingsExW, ChangeDisplaySettingsW, EnumDisplayDevicesW, EnumDisplaySettingsExW,
    CDS_NORESET, CDS_SET_PRIMARY, CDS_UPDATEREGISTRY, DISP_CHANGE_SUCCESSFUL,
    ENUM_CURRENT_SETTINGS,
};

static ENABLED: AtomicBool = AtomicBool::new(false);
static RUNNING: AtomicBool = AtomicBool::new(false);

#[derive(Debug, PartialEq)]
pub enum CompatTopology {
    Skip,
    Clone,
    IddPrimary,
}

pub fn plan_topology(indirect_already_active: bool, clone_stage_ok: bool) -> CompatTopology {
    if indirect_already_active {
        CompatTopology::Skip
    } else if clone_stage_ok {
        CompatTopology::Clone
    } else {
        CompatTopology::IddPrimary
    }
}

pub fn is_enabled() -> bool {
    ENABLED.load(Ordering::SeqCst)
}

fn indirect_active() -> bool {
    active_devices().iter().any(|d| is_indirect(&d.description))
}

pub fn ensure_async() {
    // Connection close runs virtual_display_manager::reset_all(), which unplugs our
    // monitor; a later connection in the same process must re-plug, not early-return.
    if ENABLED.load(Ordering::SeqCst) && indirect_active() {
        return;
    }
    if RUNNING.swap(true, Ordering::SeqCst) {
        return;
    }
    std::thread::spawn(|| {
        match ensure() {
            Ok(CompatTopology::Skip) => {
                log::info!("compat display skipped, an indirect display is already active");
                ENABLED.store(true, Ordering::SeqCst);
            }
            Ok(top) => {
                log::info!("compat display enabled: {top:?}");
                ENABLED.store(true, Ordering::SeqCst);
            }
            Err(e) => log::warn!("compat display failed: {e}"),
        }
        RUNNING.store(false, Ordering::SeqCst);
    });
}

struct Device {
    name: Vec<u16>,
    description: String,
    flags: u32,
}

fn active_devices() -> Vec<Device> {
    let mut devices = Vec::new();
    let mut dd: DISPLAY_DEVICEW = unsafe { std::mem::zeroed() };
    dd.cb = std::mem::size_of::<DISPLAY_DEVICEW>() as _;
    let mut i = 0;
    loop {
        if unsafe { EnumDisplayDevicesW(std::ptr::null_mut(), i, &mut dd, 0) } == FALSE {
            break;
        }
        i += 1;
        if dd.StateFlags & DISPLAY_DEVICE_ACTIVE == 0 {
            continue;
        }
        let name: Vec<u16> = dd
            .DeviceName
            .iter()
            .copied()
            .take_while(|c| *c != 0)
            .chain(std::iter::once(0))
            .collect();
        let description = String::from_utf16_lossy(&dd.DeviceString)
            .trim_end_matches('\0')
            .to_string();
        devices.push(Device {
            name,
            description,
            flags: dd.StateFlags,
        });
    }
    devices
}

fn is_indirect(description: &str) -> bool {
    description.contains("IddDriver") || description.contains("Virtual Display")
}

fn current_devmode(name: &[u16]) -> Option<DEVMODEW> {
    let mut dm: DEVMODEW = unsafe { std::mem::zeroed() };
    dm.dmSize = std::mem::size_of::<DEVMODEW>() as _;
    if unsafe { EnumDisplaySettingsExW(name.as_ptr(), ENUM_CURRENT_SETTINGS, &mut dm, 0) } == FALSE {
        return None;
    }
    if dm.dmPelsWidth == 0 || dm.dmPelsHeight == 0 {
        return None;
    }
    Some(dm)
}

fn stage(name: &[u16], dm: &mut DEVMODEW, flags: u32) -> bool {
    unsafe {
        ChangeDisplaySettingsExW(
            name.as_ptr(),
            dm,
            std::ptr::null_mut(),
            flags | CDS_UPDATEREGISTRY | CDS_NORESET,
            std::ptr::null_mut(),
        ) == DISP_CHANGE_SUCCESSFUL
    }
}

fn apply() -> ResultType<()> {
    if unsafe { ChangeDisplaySettingsW(std::ptr::null_mut(), 0) } != DISP_CHANGE_SUCCESSFUL {
        bail!("ChangeDisplaySettingsW apply failed");
    }
    Ok(())
}

fn stage_clone(primary: &Device, idd: &Device) -> bool {
    let Some(mut dm_p) = current_devmode(&primary.name) else {
        return false;
    };
    let mut dm_v: DEVMODEW = unsafe { std::mem::zeroed() };
    dm_v.dmSize = std::mem::size_of::<DEVMODEW>() as _;
    dm_v.dmPelsWidth = dm_p.dmPelsWidth;
    dm_v.dmPelsHeight = dm_p.dmPelsHeight;
    let (px, py) = unsafe { (dm_p.u1.s2().dmPosition.x, dm_p.u1.s2().dmPosition.y) };
    unsafe {
        dm_v.u1.s2_mut().dmPosition.x = px;
        dm_v.u1.s2_mut().dmPosition.y = py;
    }
    dm_v.dmDisplayFrequency = dm_p.dmDisplayFrequency;
    dm_v.dmBitsPerPel = 32;
    dm_v.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_POSITION | DM_DISPLAYFREQUENCY | DM_BITSPERPEL;
    let ok_p = stage(&primary.name, &mut dm_p, CDS_SET_PRIMARY);
    let ok_v = stage(&idd.name, &mut dm_v, 0);
    ok_p && ok_v
}

fn stage_idd_primary(idd: &Device) -> ResultType<()> {
    let Some(mut dm) = current_devmode(&idd.name) else {
        bail!("no current mode for virtual display");
    };
    unsafe {
        dm.u1.s2_mut().dmPosition.x = 0;
        dm.u1.s2_mut().dmPosition.y = 0;
    }
    dm.dmFields |= DM_POSITION;
    if !stage(&idd.name, &mut dm, CDS_SET_PRIMARY) {
        bail!("staging virtual display as primary failed");
    }
    apply()
}

fn ensure() -> ResultType<CompatTopology> {
    use crate::virtual_display_manager;
    if !virtual_display_manager::is_virtual_display_supported() {
        bail!("virtual display not supported on this Windows version");
    }
    let devices = active_devices();
    if devices.iter().any(|d| is_indirect(&d.description)) {
        return Ok(CompatTopology::Skip);
    }
    virtual_display_manager::plug_in_monitor(0, vec![])?;
    let amyuni = virtual_display_manager::AMYUNI_IDD_DEVICE_STRING.trim_end_matches('\0');
    let mut idd = None;
    for _ in 0..100 {
        idd = active_devices()
            .into_iter()
            .find(|d| d.description.starts_with(amyuni));
        if idd.is_some() {
            break;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    let Some(idd) = idd else {
        bail!("virtual display did not become active");
    };
    // plug_in_monitor spawns a thread that resets the new monitor to 1920x1080;
    // let it finish before staging topology, otherwise it overrides the clone mode.
    std::thread::sleep(Duration::from_millis(3500));
    let Some(primary) = active_devices()
        .into_iter()
        .find(|d| d.flags & DISPLAY_DEVICE_PRIMARY_DEVICE != 0)
    else {
        bail!("no primary display found");
    };
    let plan = plan_topology(false, stage_clone(&primary, &idd));
    match plan {
        CompatTopology::Clone => apply()?,
        CompatTopology::IddPrimary => {
            // Clear the primary claim left pending by the failed clone staging,
            // otherwise the batch would contain two CDS_SET_PRIMARY stages.
            if let Some(mut dm_p) = current_devmode(&primary.name) {
                stage(&primary.name, &mut dm_p, 0);
            }
            stage_idd_primary(&idd)?
        }
        CompatTopology::Skip => {}
    }
    Ok(plan)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn active_indirect_display_skips_compat_topology() {
        assert_eq!(plan_topology(true, true), CompatTopology::Skip);
        assert_eq!(plan_topology(true, false), CompatTopology::Skip);
    }

    #[test]
    fn clone_preferred_with_idd_primary_fallback() {
        assert_eq!(plan_topology(false, true), CompatTopology::Clone);
        assert_eq!(plan_topology(false, false), CompatTopology::IddPrimary);
    }

    #[test]
    fn compat_disabled_by_default_so_healthy_capture_stays_dxgi() {
        assert!(!is_enabled());
    }
}