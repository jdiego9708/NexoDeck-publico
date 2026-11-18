//! Deteccion de Vulkan por `dlopen`, sin linkear contra el loader.
//!
//! Sirve para una sola pregunta: **¿este equipo puede correr la build Vulkan
//! de llama.cpp?** Vulkan es el unico backend de GPU que cubre AMD e Intel en
//! Windows sin SDK del fabricante, asi que de esta respuesta depende que el
//! usuario descargue el runtime acelerado o el de CPU.
//!
//! Se carga `vulkan-1.dll` / `libvulkan.so.1` en runtime con `libloading` —
//! mismo patron que `AdlTemperatureReader` en `gpu_windows.rs`, y por el mismo
//! motivo: linkear estaticamente obligaria a tener el loader instalado para
//! que el binario arranque siquiera.
//!
//! **No alcanza con que la DLL exista.** Un equipo puede tener el loader (lo
//! instalan un monton de drivers y juegos) y cero ICDs registrados, o un ICD
//! roto. Por eso se crea una instancia de verdad y se cuentan los dispositivos
//! fisicos: cero dispositivos significa "hay loader pero no hay GPU usable",
//! que es exactamente el caso en el que descargar la build Vulkan seria tirar
//! GB a la basura.

use std::ffi::{c_char, c_void};

use libloading::{Library, Symbol};

const VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO: u32 = 1;
const VK_SUCCESS: i32 = 0;
/// `vkEnumeratePhysicalDevices` devuelve esto cuando el buffer que le pasamos
/// entra parcialmente. Para un conteo no es un error.
const VK_INCOMPLETE: i32 = 5;

type VkInstance = *mut c_void;
type VkPhysicalDevice = *mut c_void;

/// Layout exacto de `VkInstanceCreateInfo` (vulkan_core.h). `#[repr(C)]` mete
/// el mismo padding que el compilador de C en x86_64, asi que no hace falta
/// declararlo a mano.
#[repr(C)]
struct VkInstanceCreateInfo {
    s_type: u32,
    p_next: *const c_void,
    flags: u32,
    p_application_info: *const c_void,
    enabled_layer_count: u32,
    pp_enabled_layer_names: *const *const c_char,
    enabled_extension_count: u32,
    pp_enabled_extension_names: *const *const c_char,
}

// `VKAPI_CALL` es `__stdcall` en Win32 y la convencion de C en el resto;
// `extern "system"` resuelve exactamente eso segun el target.
type VkCreateInstanceFn =
    unsafe extern "system" fn(*const VkInstanceCreateInfo, *const c_void, *mut VkInstance) -> i32;
type VkEnumeratePhysicalDevicesFn =
    unsafe extern "system" fn(VkInstance, *mut u32, *mut VkPhysicalDevice) -> i32;
type VkDestroyInstanceFn = unsafe extern "system" fn(VkInstance, *const c_void);

#[cfg(target_os = "windows")]
const LOADER_NAMES: &[&str] = &["vulkan-1.dll"];
#[cfg(not(target_os = "windows"))]
const LOADER_NAMES: &[&str] = &["libvulkan.so.1", "libvulkan.so"];

/// Cuenta los dispositivos fisicos que Vulkan puede ver.
///
/// - `None`  → no hay loader, o no se pudo crear una instancia (ICD ausente o
///   roto). En los dos casos la conclusion practica es la misma: no usar la
///   build Vulkan.
/// - `Some(0)` → hay loader pero ningun dispositivo. Tampoco sirve, pero se
///   distingue para poder explicarselo al usuario ("Vulkan instalado, sin
///   GPU compatible") en vez de decir "Vulkan no disponible".
/// - `Some(n)` → n GPUs utilizables.
pub fn physical_device_count() -> Option<u32> {
    let library = LOADER_NAMES
        .iter()
        .find_map(|name| unsafe { Library::new(*name) }.ok())?;

    unsafe {
        let create_instance: Symbol<VkCreateInstanceFn> =
            library.get(b"vkCreateInstance\0").ok()?;
        let enumerate: Symbol<VkEnumeratePhysicalDevicesFn> =
            library.get(b"vkEnumeratePhysicalDevices\0").ok()?;
        let destroy_instance: Symbol<VkDestroyInstanceFn> =
            library.get(b"vkDestroyInstance\0").ok()?;

        // Instancia minima: sin capas, sin extensiones, sin
        // `VkApplicationInfo` (es opcional y pedir una version concreta solo
        // agrega motivos para que falle). Solo queremos que el loader levante
        // los ICDs y nos deje enumerar.
        let create_info = VkInstanceCreateInfo {
            s_type: VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            p_next: std::ptr::null(),
            flags: 0,
            p_application_info: std::ptr::null(),
            enabled_layer_count: 0,
            pp_enabled_layer_names: std::ptr::null(),
            enabled_extension_count: 0,
            pp_enabled_extension_names: std::ptr::null(),
        };

        let mut instance: VkInstance = std::ptr::null_mut();
        if create_instance(&create_info, std::ptr::null(), &mut instance) != VK_SUCCESS
            || instance.is_null()
        {
            return None;
        }

        // Patron de dos llamadas de Vulkan: con `pPhysicalDevices` nulo solo
        // devuelve el conteo. No hace falta la segunda porque no necesitamos
        // los handles.
        let mut count: u32 = 0;
        let status = enumerate(instance, &mut count, std::ptr::null_mut());

        destroy_instance(instance, std::ptr::null());

        if status == VK_SUCCESS || status == VK_INCOMPLETE {
            Some(count)
        } else {
            None
        }
    }
}
