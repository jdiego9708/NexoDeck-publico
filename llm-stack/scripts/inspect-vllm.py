"""Se ejecuta DENTRO del contenedor de vLLM (lo lanza inspect-vllm-image.sh). Informa de versiones,
de si la GPU es visible y de que arquitecturas, cuantizaciones y kernels trae esta imagen, para
contrastarlo con lo que asume la receta (docs 02 y 04) antes de arrancar ningun modelo.
"""
import importlib
import sys

NEEDED_ARCHITECTURES = [
    "Gemma4UnifiedForConditionalGeneration",
    "Qwen3_5ForConditionalGeneration",
    "Qwen3MoeForCausalLM",
]


def section(title):
    print(f"\n== {title}")


def attempt(label, function):
    try:
        function()
    except Exception as error:  # informar y seguir: interesa ver todo lo que falle
        print(f"   {label}: ERROR {type(error).__name__}: {error}")


def versions():
    for module_name in ("vllm", "torch", "transformers", "flashinfer", "b12x", "cutlass"):
        try:
            module = importlib.import_module(module_name)
            print(f"   {module_name}: {getattr(module, '__version__', 'sin __version__')}")
        except Exception as error:
            print(f"   {module_name}: NO DISPONIBLE ({type(error).__name__})")


def gpu():
    import torch

    print(f"   cuda disponible: {torch.cuda.is_available()}  (torch compilado con CUDA {torch.version.cuda})")
    if torch.cuda.is_available():
        free, total = torch.cuda.mem_get_info()
        print(f"   {torch.cuda.get_device_name(0)}  capability={torch.cuda.get_device_capability(0)}")
        print(f"   VRAM libre {free / 1024 ** 3:.2f} GiB de {total / 1024 ** 3:.2f} GiB")


def architectures():
    from vllm.model_executor.models import ModelRegistry

    supported = set(ModelRegistry.get_supported_archs())
    print(f"   {len(supported)} arquitecturas registradas")
    for name in NEEDED_ARCHITECTURES:
        print(f"   {'OK ' if name in supported else 'FALTA'} {name}")


def quantization():
    from vllm.model_executor.layers.quantization import QUANTIZATION_METHODS

    methods = sorted(QUANTIZATION_METHODS)
    wanted = ["awq", "awq_marlin", "modelopt", "modelopt_fp4", "fp8", "gptq_marlin", "mxfp4"]
    print(f"   {len(methods)} metodos. Los que interesan: "
          + ", ".join(f"{m}={'si' if m in methods else 'NO'}" for m in wanted))


def kernels():
    candidates = [
        ("vllm.model_executor.kernels.linear.nvfp4.b12x", "B12xNvFp4LinearKernel"),
        ("vllm.model_executor.kernels.linear.scaled_mm.b12x", "B12xFp8BlockScaledMMKernel"),
    ]
    for module_name, class_name in candidates:
        try:
            module = importlib.import_module(module_name)
            kernel = getattr(module, class_name)
            print(f"   {class_name}.is_supported(120) = {kernel.is_supported(compute_capability=120)}")
        except Exception as error:
            print(f"   {class_name}: no disponible ({type(error).__name__}: {error})")


section("Versiones")
attempt("versiones", versions)
section("GPU")
attempt("gpu", gpu)
section("Arquitecturas necesarias")
attempt("arquitecturas", architectures)
section("Cuantizaciones")
attempt("cuantizaciones", quantization)
section("Kernels b12x para SM120")
attempt("kernels", kernels)
sys.exit(0)
