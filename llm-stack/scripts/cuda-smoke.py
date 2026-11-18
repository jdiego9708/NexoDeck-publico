"""Prueba minima de CUDA dentro del contenedor de vLLM: inicializa el contexto, reserva memoria, hace
una operacion y sincroniza, midiendo cada fase. Sirve para distinguir un fallo de vLLM de una GPU
o un controlador de WSL2 en mal estado (los arranques se quedan parados en la inicializacion de
CUDA, sin ninguna excepcion, y con un proceso al 100 % de CPU).

Lo lanza check-cuda.sh, con un limite de tiempo. Si esto no termina, el problema NO es vLLM.
"""
import time

import torch

started = time.perf_counter()


def step(label):
    print(f"{time.perf_counter() - started:6.2f} s  {label}", flush=True)


step("torch importado")
torch.cuda.init()
step(f"CUDA inicializado: {torch.cuda.get_device_name(0)}")
free, total = torch.cuda.mem_get_info()
step(f"memoria libre segun CUDA: {free / 1024 ** 3:.2f} de {total / 1024 ** 3:.2f} GiB")
tensor = torch.ones(256 * 1024 * 1024, dtype=torch.uint8, device="cuda")  # 256 MiB
step("reservados 256 MiB en la GPU")
result = (tensor.float().sum()).item()
step(f"operacion y sincronizacion correctas (suma={result:.0f})")
pinned = torch.empty(64 * 1024 * 1024, dtype=torch.uint8).pin_memory()
step(f"memoria fijada de 64 MiB creada ({pinned.numel() // 1024 // 1024} MiB)")
print("CUDA OK")
