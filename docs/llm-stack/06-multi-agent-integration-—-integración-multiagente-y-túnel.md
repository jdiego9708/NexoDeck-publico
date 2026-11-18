---
date: 2026-09-17
---
# 06-Multi-Agent-Integration — Integración Multiagente y Túnel

# 06-Multi-Agent-Integration — Integración Multiagente y Túnel

Documentación completa para integrar el stack vLLM con aplicaciones cliente, configurar concurrencia multiagente, gestionar el ciclo de vida de los modelos vía API, y exponer el endpoint de forma segura vía Cloudflare Tunnel.

Este documento es **solo de referencia y configuración**. No contiene scripts de arranque ni automatizaciones; solo comandos ejecutables, explicaciones de cada decisión, y criterios de verificación.

---

## Índice

1. [Contexto y Objetivos](#1-contexto-y-objetivos)
2. [Decisiones Arquitectónicas](#2-decisiones-arquitectónicas)
3. [Paso 1 — Endpoints del Stack](#3-paso-1--endpoints-del-stack)
4. [Paso 2 — Cliente Python Básico](#4-paso-2--cliente-python-básico)
5. [Paso 3 — Concurrencia Multiagente](#5-paso-3--concurrencia-multiagente)
6. [Paso 4 — Gestión de Sleep Mode vía API](#6-paso-4--gestión-de-sleep-mode-vía-api)
7. [Paso 5 — Configuración de Agentes por Tipo](#7-paso-5--configuración-de-agentes-por-tipo)
8. [Paso 6 — Integración con OpenCode y otras herramientas](#8-paso-6--integración-con-opencode-y-otras-herramientas)
9. [Paso 7 — Túnel Seguro con Cloudflare](#9-paso-7--túnel-seguro-con-cloudflare)
10. [Paso 8 — Autenticación y Rate Limiting](#10-paso-8--autenticación-y-rate-limiting)
11. [Paso 9 — Monitoreo y Logs](#11-paso-9--monitoreo-y-logs)
12. [Checklist Final](#12-checklist-final)
13. [Advertencias Críticas](#13-advertencias-críticas)
14. [Referencias](#14-referencias)

---

## 1. Contexto y Objetivos

Este documento asume que ya completaste el `05-Semantic-Router.md`. Debes tener:

- Los 3 servidores vLLM corriendo:
  - Puerto 8000: Qwen3-Coder-30B NVFP4 (complejo)
  - Puerto 8001: Gemma 4 12B AWQ (rápido)
  - Puerto 8002: Qwen 3.5 4B NVFP4 (router/meta)
- Router semántico corriendo en puerto 8888.
- Router Replay acumulando registros en `replay.db`.
- Dashboard accesible en puerto 8700.
- Sleep Mode funcionando.

El objetivo de esta fase es **conectar tu aplicación al stack**, configurar la concurrencia multiagente, y exponer el endpoint vía túnel seguro.

### Topología completa
Internet (opcional)
│
▼
┌───────────────────────┐
│ Cloudflare Tunnel │
│ api.tudominio.com │
└───────────┬───────────┘
│
▼
┌─────────────────────────────────────────────────────────┐
│ WINDOWS 11 (host) │
│ ┌───────────────────────────────────────────────────┐ │
│ │ WSL2 (Ubuntu) │ │
│ │ │ │
│ │ ┌─────────────────────────────────────────────┐ │ │
│ │ │ vLLM-SR (puerto 8888) │ │ │
│ │ └────────────┬────────────────────────────────┘ │ │
│ │ │ │ │
│ │ ┌─────────┼─────────┬─────────────┐ │ │
│ │ ▼ ▼ ▼ ▼ │ │
│ │ ┌─────┐ ┌─────┐ ┌─────┐ ┌──────────────┐ │ │
│ │ │8000 │ │8001 │ │8002 │ │RSIAgent 8890 │ │ │
│ │ │Qwen │ │Gemma│ │Qwen │ │(opcional) │ │ │
│ │ │3-30B│ │4-12B│ │3.5-4B│ │ │ │ │
│ │ └─────┘ └─────┘ └─────┘ └──────────────┘ │ │
│ │ │ │
│ │ ┌─────────────────────────────────────────────┐ │ │
│ │ │ Router Replay (SQLite) │ │ │
│ │ └─────────────────────────────────────────────┘ │ │
│ └───────────────────────────────────────────────────┘ │
│ │
│ ┌───────────────────────────────────────────────────┐ │
│ │ Cloudflare Tunnel (cloudflared.exe) │ │
│ └───────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
│
▼
┌───────────────────────┐
│ Tu App / OpenCode │
│ / Cliente Python │
└───────────────────────┘

---

## 2. Decisiones Arquitectónicas

| Decisión | Alternativa descartada | Razón |
|:---|:---|:---|
| **Cliente siempre contra puerto 8888** | Llamadas directas a 8000/8001/8002 | El router decide el modelo óptimo. Los puertos backend solo se usan para debugging. |
| **SDK de OpenAI oficial** | `requests` crudo, `httpx` | El SDK maneja serialización, retries, streaming, y es compatible con cualquier API OpenAI. |
| **`AsyncOpenAI` para multiagente** | `OpenAI` síncrono | vLLM usa Continuous Batching. Con `asyncio`, puedes lanzar N agentes sin bloquear. |
| **Sleep Mode vía API REST** | Scripts de shell | El ciclo de vida del modelo (dormir/despertar) es responsabilidad de la app, no del shell. |
| **Cloudflare Tunnel** | ngrok, Tailscale Funnel, port forwarding | Cloudflare Tunnel no requiere abrir puertos en el router, incluye SSL automático, y permite Cloudflare Access. |
| **Cloudflare Access para autenticación** | API key en el router | Access añade autenticación por identidad (email, SSO) sin modificar el código del router. |
| **Túnel en Windows, no en WSL2** | cloudflared dentro de Ubuntu | El túnel en Windows simplifica la configuración de red y evita conflictos con `localhostForwarding`. |
| **Rate limiting en el router o en Access** | Rate limiting en la app | Centralizado, más fácil de ajustar sin redespliegue. |

---

## 3. Paso 1 — Endpoints del Stack

### 3.1 Tabla completa de endpoints

| Servicio | Puerto | Endpoint | Protocolo | Uso |
|:---|:---|:---|:---|:---|
| **vLLM Complejo** | 8000 | `http://localhost:8000/v1` | HTTP | Qwen3-Coder-30B (debugging) |
| **vLLM Rápido** | 8001 | `http://localhost:8001/v1` | HTTP | Gemma 4 12B (debugging) |
| **vLLM Router** | 8002 | `http://localhost:8002/v1` | HTTP | Qwen 3.5 4B (debugging) |
| **vLLM-SR** | 8888 | `http://localhost:8888/v1` | HTTP | **Enrutamiento automático (producción)** |
| **Dashboard vLLM-SR** | 8700 | `http://localhost:8700` | HTTP | Monitoreo |
| **Métricas Prometheus** | 9190 | `http://localhost:9190/metrics` | HTTP | Métricas |
| **RSIAgent** | 8890 | `http://localhost:8890` | HTTP | Auto-mejora (Fase 8) |

### 3.2 Puertos expuestos al exterior

| Puerto | Expuesto | Razón |
|:---|:---|:---|
| **8888** | ✓ Sí (vía túnel) | Enrutador semántico; punto de entrada único |
| **8700** | ⚠️ Opcional (solo IP local) | Dashboard; útil si trabajas desde otra máquina |
| **8000/8001/8002** | ✗ No | Tienen `VLLM_SERVER_DEV_MODE=1`, endpoints peligrosos |
| **9190** | ✗ No | Métricas Prometheus internas |

### 3.3 Verificar que todos responden

for port in 8000 8001 8002 8888; do
  echo -n "Puerto $port: "
  curl -s http://localhost:$port/v1/models | python -c "import sys, json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null || echo "✗ No responde"
done

Salida esperada:

text
Puerto 8000: qwen3-coder-30b
Puerto 8001: gemma-4-12b
Puerto 8002: qwen3.5-4b
Puerto 8888: qwen3-coder-30b
4. Paso 2 — Cliente Python Básico
4.1 Instalación
En tu entorno Python de desarrollo (no en el venv de vLLM):

bash
pip install openai httpx
4.2 Cliente mínimo
python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8888/v1",
    api_key="dummy"
)

response = client.chat.completions.create(
    model="auto",
    messages=[
        {"role": "system", "content": "You are a senior Python developer."},
        {"role": "user", "content": "Write a function to merge two sorted lists."}
    ],
    temperature=0.7,
    top_p=0.8,
    max_tokens=1024
)

print(response.choices[0].message.content)
4.3 Explicación
Parámetro	Valor	Razón
base_url	http://localhost:8888/v1	Apunta al router, no a los modelos backend.
api_key	"dummy"	vLLM local no valida; el SDK requiere un valor.
model	"auto"	Activa el enrutamiento automático.
messages	Formato OpenAI	Estándar compatible con cualquier SDK.
temperature	0.7	Balance entre creatividad y determinismo.
top_p	0.8	Nucleus sampling.
max_tokens	1024	Limita la generación.
4.4 Streaming
Para respuestas largas, activa streaming para que el usuario vea el texto conforme se genera:

python
stream = client.chat.completions.create(
    model="auto",
    messages=[{"role": "user", "content": "Write a 500-line Python script."}],
    stream=True,
    max_tokens=2048
)

for chunk in stream:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)
4.5 Manejo de errores
python
from openai import OpenAI, APIError, APIConnectionError, RateLimitError
import time

client = OpenAI(base_url="http://localhost:8888/v1", api_key="dummy")

def chat_with_retry(messages, max_retries=3):
    for attempt in range(max_retries):
        try:
            return client.chat.completions.create(
                model="auto",
                messages=messages,
                max_tokens=1024
            )
        except APIConnectionError:
            print(f"Error de conexión. Reintento {attempt + 1}/{max_retries}")
            time.sleep(2 ** attempt)
        except RateLimitError:
            print(f"Rate limit. Reintento {attempt + 1}/{max_retries}")
            time.sleep(5)
        except APIError as e:
            print(f"Error API: {e}")
            raise
    raise RuntimeError("Máximo de reintentos alcanzado")
5. Paso 3 — Concurrencia Multiagente
5.1 ¿Por qué AsyncOpenAI?
vLLM usa Continuous Batching y PagedAttention, lo que le permite procesar múltiples peticiones simultáneamente. Para aprovechar esto, tu cliente debe enviar peticiones concurrentes sin bloquearse.

Con AsyncOpenAI y asyncio.gather, lanzas N agentes en paralelo y esperas a que todos terminen. El throughput total es mucho mayor que ejecutarlos secuencialmente.

5.2 Ejemplo con 8 agentes concurrentes
python
import asyncio
from openai import AsyncOpenAI

async def agent_task(client, prompt, agent_id):
    """Ejecuta una tarea de agente."""
    try:
        response = await client.chat.completions.create(
            model="auto",
            messages=[
                {"role": "system", "content": f"You are agent {agent_id}, an expert Python developer."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.7,
            max_tokens=1024
        )
        return agent_id, response.choices[0].message.content
    except Exception as e:
        return agent_id, f"ERROR: {e}"

async def main():
    client = AsyncOpenAI(
        base_url="http://localhost:8888/v1",
        api_key="dummy",
        timeout=120.0
    )

    prompts = [
        "Write a binary search in Python",
        "Explain the Observer pattern",
        "Write a REST API endpoint in FastAPI",
        "Refactor this SQL query for performance",
        "Create a Dockerfile for a Python app",
        "Write unit tests for a calculator",
        "Design a database schema for a blog",
        "Optimize this regex pattern"
    ]

    tasks = [
        agent_task(client, prompt, f"agent_{i}")
        for i, prompt in enumerate(prompts)
    ]

    results = await asyncio.gather(*tasks)

    for agent_id, result in results:
        print(f"\n{'='*60}")
        print(f"{agent_id}:")
        print(f"{'='*60}")
        print(result[:500])
        print()

if __name__ == "__main__":
    asyncio.run(main())
5.3 Semáforo para limitar concurrencia
Si lanzas más agentes de los que la GPU puede manejar, vLLM encolará las peticiones. Para evitar saturación, usa un semáforo:

python
import asyncio
from openai import AsyncOpenAI

MAX_CONCURRENT = 6  # Ajustar según VRAM disponible

async def agent_task(client, prompt, agent_id, semaphore):
    async with semaphore:
        response = await client.chat.completions.create(
            model="auto",
            messages=[{"role": "user", "content": prompt}],
            max_tokens=1024
        )
        return agent_id, response.choices[0].message.content

async def main():
    client = AsyncOpenAI(base_url="http://localhost:8888/v1", api_key="dummy")
    semaphore = asyncio.Semaphore(MAX_CONCURRENT)

    prompts = [f"Task {i}: write a Python function" for i in range(20)]

    tasks = [
        agent_task(client, prompt, f"agent_{i}", semaphore)
        for i, prompt in enumerate(prompts)
    ]

    results = await asyncio.gather(*tasks)
    print(f"Completadas {len(results)} tareas")

if __name__ == "__main__":
    asyncio.run(main())
5.4 Ajuste del límite de concurrencia
Estado del stack	MAX_CONCURRENT recomendado
Router + Rápido (~9.5 GB usados)	8-12
Router + Complejo (~12.5 GB usados)	4-6
Solo Rápido (~9 GB usados)	10-15
Solo Complejo (~12 GB usados)	4-6
Verificar tras ajustar:

bash
watch -n 2 nvidia-smi
Si la VRAM usada supera el 95%, reducir MAX_CONCURRENT.

6. Paso 4 — Gestión de Sleep Mode vía API
6.1 ¿Por qué gestionar Sleep Mode desde la app?
El router semántico no sabe cuándo necesitarás el modelo complejo con antelación. Tu app, en cambio, sí puede predecir según el contexto:

Si el usuario empieza a escribir código complejo → despertar complejo.

Si el usuario hace preguntas rápidas → despertar rápido.

Gestionar Sleep Mode desde la app permite pre-calentar el modelo antes de que llegue la petición, eliminando la latencia del cambio.

6.2 Cliente de gestión
python
import httpx
import asyncio

class ModelManager:
    """Gestiona el ciclo de vida de los modelos vLLM vía API."""

    def __init__(self):
        self.ports = {
            "router": 8002,
            "fast": 8001,
            "complex": 8000
        }

    async def is_sleeping(self, model_name: str) -> bool:
        """Consulta si un modelo está dormido."""
        port = self.ports[model_name]
        async with httpx.AsyncClient(timeout=10.0) as client:
            r = await client.get(f"http://localhost:{port}/is_sleeping")
            return r.json().get("is_sleeping", False)

    async def sleep(self, model_name: str, level: int = 1):
        """Duerme un modelo (Level 1: pesos a RAM, Level 2: descarta)."""
        port = self.ports[model_name]
        async with httpx.AsyncClient(timeout=30.0) as client:
            await client.post(f"http://localhost:{port}/sleep?level={level}")

    async def wake(self, model_name: str):
        """Despierta un modelo."""
        port = self.ports[model_name]
        async with httpx.AsyncClient(timeout=30.0) as client:
            await client.post(f"http://localhost:{port}/wake_up")

    async def wake_with_reload(self, model_name: str):
        """Despierta un modelo tras Level 2 (requiere reload)."""
        port = self.ports[model_name]
        async with httpx.AsyncClient(timeout=60.0) as client:
            await client.post(f"http://localhost:{port}/wake_up")
            await client.post(f"http://localhost:{port}/reload_weights")
            await client.post(f"http://localhost:{port}/reset_prefix_cache")

    async def switch_to(self, target: str):
        """Cambia el modelo activo.

        Args:
            target: "router", "fast", "complex", "router+fast", "router+complex"
        """
        if target == "router+fast":
            await self.sleep("complex", level=1)
            await self.wake("router")
            await self.wake("fast")
        elif target == "router+complex":
            await self.sleep("fast", level=1)
            await self.wake("router")
            await self.wake("complex")
        elif target == "complex":
            await self.sleep("router", level=1)
            await self.sleep("fast", level=1)
            await self.wake("complex")
        elif target == "fast":
            await self.sleep("router", level=1)
            await self.sleep("complex", level=1)
            await self.wake("fast")
6.3 Uso
python
async def main():
    manager = ModelManager()

    # Estado inicial: router + rápido
    await manager.switch_to("router+fast")

    # Usuario empieza una tarea compleja
    await manager.switch_to("router+complex")

    # Tarea compleja termina
    await manager.switch_to("router+fast")

asyncio.run(main())
6.4 Pre-calentamiento predictivo
python
import re

COMPLEX_KEYWORDS = re.compile(
    r"\b(refactor|architecture|design pattern|optimize|system design|debug complex)\b",
    re.IGNORECASE
)

async def preload_model(prompt: str, manager: ModelManager):
    """Pre-carga el modelo adecuado según el prompt."""
    if COMPLEX_KEYWORDS.search(prompt) or len(prompt) > 800:
        await manager.switch_to("router+complex")
    else:
        await manager.switch_to("router+fast")
7. Paso 5 — Configuración de Agentes por Tipo
7.1 Tipos de agentes
Tipo	Modelo destino	Endpoint	Uso
Simple	Gemma 4 12B	8001 o 8888 (auto)	Autocompletado, consultas rápidas
Normal	Gemma 4 12B	8001 o 8888 (auto)	Edición, refactoring simple
Complejo	Qwen3-Coder-30B	8000 o 8888 (auto)	Arquitectura, debugging profundo
Meta	Qwen 3.5 4B	8002 o 8888 (auto)	Clasificación, tool-calling
Auto	Router decide	8888	Enrutamiento automático (recomendado)
7.2 Ejemplo de agente especializado
python
from dataclasses import dataclass
from typing import Literal
from openai import AsyncOpenAI

@dataclass
class AgentConfig:
    name: str
    role: Literal["simple", "normal", "complex", "meta", "auto"]
    system_prompt: str

class Agent:
    def __init__(self, config: AgentConfig, client: AsyncOpenAI):
        self.config = config
        self.client = client

    async def run(self, user_message: str, **kwargs) -> str:
        response = await self.client.chat.completions.create(
            model="auto" if self.config.role == "auto" else self.config.role,
            messages=[
                {"role": "system", "content": self.config.system_prompt},
                {"role": "user", "content": user_message}
            ],
            **kwargs
        )
        return response.choices[0].message.content

# Definir agentes
agents = [
    AgentConfig(
        name="quick_helper",
        role="auto",
        system_prompt="You are a fast coding assistant. Answer concisely."
    ),
    AgentConfig(
        name="architect",
        role="complex",
        system_prompt="You are a senior software architect. Design scalable systems."
    ),
    AgentConfig(
        name="code_reviewer",
        role="auto",
        system_prompt="You review Python code for bugs, performance, and style."
    )
]
7.3 Ejecución paralela de agentes
python
async def run_agents_parallel(client, agents, message):
    tasks = [agent.run(message) for agent in agents]
    results = await asyncio.gather(*tasks)
    return dict(zip([a.config.name for a in agents], results))
8. Paso 6 — Integración con OpenCode y otras herramientas
8.1 OpenCode
OpenCode es un editor/IDE con integración de IA. Se puede configurar para usar tu endpoint local.

Configuración típica (buscar el archivo de configuración de OpenCode, típicamente ~/.config/opencode/config.json o similar):

json
{
  "providers": {
    "local-vllm": {
      "type": "openai",
      "baseUrl": "http://localhost:8888/v1",
      "apiKey": "dummy",
      "models": {
        "auto": {
          "name": "Auto (router)",
          "maxTokens": 16384
        },
        "gemma-4-12b": {
          "name": "Gemma 4 12B (rápido)",
          "maxTokens": 8192
        },
        "qwen3-coder-30b": {
          "name": "Qwen3-Coder-30B (complejo)",
          "maxTokens": 16384
        }
      }
    }
  },
  "defaultProvider": "local-vllm",
  "defaultModel": "auto"
}
Verificar: abrir OpenCode y comprobar que el proveedor aparece en la lista.

8.2 Continue.dev (VS Code)
Continue es una extensión de VS Code para asistencia de código con IA. Configuración en ~/.continue/config.json:

json
{
  "models": [
    {
      "title": "vLLM Local (auto)",
      "provider": "openai",
      "model": "auto",
      "apiBase": "http://localhost:8888/v1",
      "apiKey": "dummy"
    },
    {
      "title": "vLLM Local (complejo)",
      "provider": "openai",
      "model": "qwen3-coder-30b",
      "apiBase": "http://localhost:8000/v1",
      "apiKey": "dummy"
    }
  ],
  "tabAutocompleteModel": {
    "title": "Gemma 4 12B (autocomplete)",
    "provider": "openai",
    "model": "gemma-4-12b",
    "apiBase": "http://localhost:8001/v1",
    "apiKey": "dummy"
  }
}
8.3 Aider
Aider es un asistente de código en CLI. Se configura con variables de entorno:

bash
export OPENAI_API_BASE=http://localhost:8888/v1
export OPENAI_API_KEY=dummy

aider --model openai/auto
8.4 Uso con curl
Endpoint OpenAI-compatible:

bash
curl http://localhost:8888/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer dummy" \
  -d '{
    "model": "auto",
    "messages": [{"role": "user", "content": "Write a Fibonacci function."}],
    "max_tokens": 200
  }' | python -m json.tool
Streaming:

bash
curl http://localhost:8888/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "auto", "messages": [{"role": "user", "content": "Count to 10"}], "stream": true}' \
  --no-buffer
9. Paso 7 — Túnel Seguro con Cloudflare
9.1 ¿Por qué Cloudflare Tunnel?
Alternativas:

Opción	Ventajas	Desventajas
Port forwarding	Simple	Requiere abrir puertos en el router; expone tu IP; requiere IP fija o DDNS
ngrok	Fácil de configurar	Subdominio aleatorio en plan gratis; límites de conexión
Tailscale Funnel	Buen rendimiento	Requiere instalar Tailscale; no es para acceso público
Cloudflare Tunnel	SSL automático, sin abrir puertos, Cloudflare Access, DDoS protection	Requiere dominio en Cloudflare
Cloudflare Tunnel es la opción recomendada porque:

No requiere abrir puertos en tu router.

Incluye SSL/TLS automático.

Se integra con Cloudflare Access (autenticación por identidad).

Protección DDoS de Cloudflare.

Tu IP nunca se expone.

9.2 Prerrequisitos
Un dominio registrado (ej. tudominio.com).

El dominio debe estar en Cloudflare (nameservers apuntando a Cloudflare).

Cuenta gratuita de Cloudflare.

Si no tienes dominio: puedes usar trycloudflare.com (subdominio aleatorio) para pruebas temporales.

9.3 Instalación
En Windows (PowerShell como administrador):

powershell
winget install Cloudflare.cloudflared
Verificar:

powershell
cloudflared --version
Salida esperada: cloudflared version 2025.x.x (o superior).

9.4 Autenticación
powershell
cloudflared tunnel login
Esto abre el navegador. Inicia sesión en Cloudflare y autoriza el dominio.

Resultado: se descarga un archivo cert.pem en %USERPROFILE%\.cloudflared\.

9.5 Crear túnel
powershell
cloudflared tunnel create vllm-agent
Salida esperada:

text
Tunnel credentials written to C:\Users\usuario\.cloudflared\<tunnel-id>.json
Created tunnel vllm-agent with id <tunnel-id>
Anotar el <tunnel-id> — se necesita para el archivo de configuración.

9.6 Enrutar DNS
powershell
cloudflared tunnel route dns vllm-agent api.tudominio.com
Resultado: se crea un registro CNAME en Cloudflare que apunta api.tudominio.com al túnel.

Verificar en el dashboard de Cloudflare → DNS → debe aparecer el CNAME.

9.7 Configurar el túnel
Crear archivo %USERPROFILE%\.cloudflared\config.yml:

yaml
tunnel: vllm-agent
credentials-file: C:\Users\usuario\.cloudflared\<tunnel-id>.json

ingress:
  - hostname: api.tudominio.com
    service: http://localhost:8888
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
      tcpKeepAlive: 30s
  - service: http_status:404
Explicación:

Campo	Valor	Razón
tunnel	vllm-agent	Nombre del túnel creado.
credentials-file	Ruta al JSON	Credenciales generadas por cloudflared tunnel create.
hostname	api.tudominio.com	Dominio público del túnel.
service	http://localhost:8888	Apunta al router semántico.
noTLSVerify	true	WSL2 no usa TLS en el puerto 8888 (HTTP plano).
connectTimeout	30s	Timeout para peticiones largas (modelos complejos).
tcpKeepAlive	30s	Mantiene la conexión viva.
service: http_status:404	Fallback	Responde 404 a rutas no configuradas.
9.8 Lanzar túnel
powershell
cloudflared tunnel run vllm-agent
Salida esperada:

text
2026-09-17T20:15:30Z INF Registered tunnel connection connIndex=0 ...
2026-09-17T20:15:30Z INF Route propagating ...
Dejar esta ventana abierta. El túnel se cierra si cierras la terminal.

9.9 Verificar desde Internet
En otra terminal (o desde otro dispositivo):

bash
curl https://api.tudominio.com/v1/models | python -m json.tool
Salida esperada: la lista de modelos del router.

Test de inferencia:

bash
curl https://api.tudominio.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto",
    "messages": [{"role": "user", "content": "Hello from the internet!"}],
    "max_tokens": 50
  }' | python -m json.tool
9.10 Instalar como servicio Windows (opcional)
Para que el túnel arranque automáticamente con Windows:

powershell
cloudflared service install
Verificar:

powershell
Get-Service cloudflared
Salida esperada: Status: Running.

Desinstalar:

powershell
cloudflared service uninstall
10. Paso 8 — Autenticación y Rate Limiting
10.1 ¿Por qué autenticación?
Sin autenticación, cualquiera que conozca tu URL pública puede:

Consumir tu GPU gratuitamente.

Saturar tu stack.

Extraer datos si compartes información sensible.

10.2 Opciones de autenticación
Método	Ventajas	Desventajas
Cloudflare Access	Autenticación por email/SSO, sin tocar código	Requiere configurar en Cloudflare
API key en vLLM-SR	Simple, se propaga a los modelos backend	Requiere modificar config.yaml
Basic auth en el túnel	Simple	Solo una contraseña compartida
Sin autenticación	Simple	Peligroso
Recomendación: Cloudflare Access para uso personal/compartido con identidades conocidas.

10.3 Cloudflare Access (recomendado)
Pasos:

Dashboard de Cloudflare → Zero Trust → Access → Applications.

Add an application → Self-hosted.

Application name: vLLM Agent Stack.

Session duration: 24 hours.

Application domain: api.tudominio.com.

Policies:

Name: Allowed Users.

Action: Allow.

Rules: Emails → lista de emails autorizados.

Save.

Resultado: al acceder a https://api.tudominio.com, Cloudflare pide autenticación por email. Tras verificar, se puede usar la API normalmente.

10.4 API key en vLLM-SR
Modificar config.yaml:

yaml
listeners:
  - name: api
    address: 0.0.0.0
    port: 8888
    api_key: "tu_clave_secreta_aqui"
Reiniciar el router.

Cliente:

python
client = OpenAI(
    base_url="http://127.0.0.1:8888/v1",  # cierre del fragmento cortado; ver la nota siguiente
    api_key="tu_clave_secreta_aqui",
)

---

> **Continuación escrita el 19-sep-2026.** El original de este documento se cortaba aquí, a mitad de línea, y no se ha podido recuperar (faltaba el resto de 10.4, el monitoreo, el checklist y las advertencias). Lo que sigue **no es la receta original**: es lo que se comprobó al montar el stack, para cerrar el documento sin inventar. Donde este documento y el `11-mejoras-y-decisiones.md` discrepen, manda el 11.

## 10.4b Autenticación real: la pasarela (sustituye a 10.4)

La receta ponía la clave en vLLM-SR (`api_key` en `config.yaml`) y `api_key: "dummy"` en los vLLM. **Nada de eso se usa**: vLLM-SR no se despliega (el enrutado es el modelo virtual `auto`, doc 11 apartado 7.22) y los servidores vLLM quedan atados a `127.0.0.1` sin autenticación propia. Lo único que se ofrece a los clientes es la **pasarela** (`llm-stack/gateway/`, doc 11 apartado 7.19), en `http://127.0.0.1:8888`:

```powershell
llm-gateway keys add nombre-del-cliente     # enseña la clave UNA sola vez; solo se guarda su hash
llm-gateway keys list
llm-gateway keys remove nombre-del-cliente  # surte efecto sin reiniciar
```

Cliente (cualquier SDK compatible con OpenAI sirve):

```python
import os
from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:8888/v1",
    api_key=os.environ["NEXODECK_LLM_KEY"],   # ndk_..., nunca escrita en el código
)
client.chat.completions.create(model="auto", messages=[{"role": "user", "content": "hola"}])
```

- **`model`**: `router`, `fast` o `complex` (los que estén levantados; `/v1/models` lo dice) o **`auto`**, que elige entre el Router y el trabajador del perfil.
- Solo existen `/v1/chat/completions`, `/v1/completions`, `/v1/models` y `/health`. Todo lo demás (`/sleep`, `/collective_rpc`, `/metrics`…) da 404 aunque la clave sea válida.
- Un modelo apagado da **503** con un mensaje claro, no una conexión rechazada.
- **NexoDeck ya lo usa como servicio remoto sin código nuevo** (preset `custom`, doc 11 apartado 7.21).

**Rate limiting: no implementado.** Hay un solo cliente hoy. Si hiciera falta, iría en la pasarela.

## 11. Monitoreo y logs (lo que existe hoy)

| Qué | Dónde |
|:---|:---|
| Peticiones (clave, modelo, decisión, estado, ms; **nunca prompts ni claves**) | `%LOCALAPPDATA%\nexodeck\LlmGateway\logs\gateway-AAAAMMDD.log` |
| Decisiones del modelo `auto` (una línea JSON por petición, sin texto) | `%LOCALAPPDATA%\nexodeck\LlmGateway\data\decisions.jsonl` |
| Arranque del stack | `%LOCALAPPDATA%\nexodeck\LlmGateway\logs\stack-AAAAMMDD.log` |
| Estado de cada modelo | `GET http://127.0.0.1:8888/health` (sin clave; responde al instante con lo último sondeado: `up`/`down`/`unknown`) |
| Registro de cada servidor vLLM | `~/vllm-stack/logs/vllm-<rol>.log` en WSL2; resumido con `llm-stack/scripts/log-summary.sh <rol>` |
| VRAM | `nvidia-smi` **después de dar carga** (en reposo infravalora: doc 11, 7.9) |
| Métricas Prometheus de vLLM | Cada servidor debería exponerlas en su `/metrics` (**no comprobado** en este equipo), que en cualquier caso **no se publica** por la pasarela; se leerían desde WSL2 en `127.0.0.1:800x` |

No hay métricas Prometheus de la pasarela.

## 5b. Concurrencia (medida, sustituye a las cifras de la receta)

Las cifras de `MAX_CONCURRENT` de la receta (8-12 agentes) eran de una RTX 5090 y no aplican. Medido en la RTX 5060 Ti (`bench.py`, tok/s agregados; doc 11 apartados 7.6, 7.10, 7.14):

| Modelo | 1 cliente | 4 clientes | 8 clientes | Nota |
|:---|:---|:---|:---|:---|
| Router (Qwen 3.5 4B) | 78-84 | 280-299 | 327-544 | Solo o en el perfil A: 538-544 a 8 clientes. En el perfil B, con su KV de 0.4 GiB, baja a 327-334: se encolan peticiones (atribuido al KV, no medido por separado) |
| Rápido (Gemma 4 12B, perfil A) | 41-44 | 156-172 | 299-334 | |
| Complejo (Qwen3-Coder, perfil B) | 98-100 | 252-262 | 258 | `--max-num-seqs 4`: con 8 clientes las demás **se encolan** |

Recomendación: no más de **4 agentes concurrentes sobre el Complejo** (más se encolan) y hasta **8 sobre el Router**, sabiendo que en el perfil B se encolan antes; con las dos instancias cargadas y bajo carga a la vez **se reparten la GPU en el tiempo** (no suman). Contexto útil en el perfil B: **8 192 tokens** (no los 16k de la receta).

## 12. Checklist final verificado

```
□ Start-Stack.ps1 -Profile A|B   (o solo la pasarela con -Profile none)
□ curl http://127.0.0.1:8888/health   →  los modelos del perfil salen "up"
□ Test-Gateway.ps1 termina en "TODO OK"   (autenticación, enrutado, streaming, rutas de administración, registro)
□ tools-check.py --model auto   (petición de agente con herramientas, también con streaming)
□ chat-check.py   (ningún modelo genera basura)
□ Ninguna clave en ficheros del repositorio ni en el registro
```

## 13. Advertencias críticas (verificadas)

1. **Nunca publiques los puertos de vLLM** (8000-8002). Con Sleep Mode activo abren endpoints de administración; la pasarela es la única puerta.
2. **La pasarela escucha solo en `127.0.0.1`** y habla HTTP sin TLS: si se cambia, avisa al arrancar. Para salir de la máquina hace falta un túnel o proxy con TLS.
3. **Solo se guarda el hash de cada clave**: una clave perdida no se recupera, se revoca y se crea otra.
4. **Lo que este documento planteaba y NO se ha probado:** el túnel de Cloudflare (sección 9) y la integración con OpenCode, Continue.dev y Aider (sección 8). **NexoDeck ya tiene el preset `custom`** para apuntarlo a la pasarela (ver `## 15`). El rate limiting sigue fuera de alcance, y la gestión de Sleep Mode desde el cliente ya no aplica (doc 11, 7.17).

## 14. Referencias

| Recurso | Dónde |
|:---|:---|
| Pasarela: uso, reglas de `auto`, pruebas | `llm-stack/gateway/README.md` |
| Prueba de humo contra el stack real | `llm-stack/scripts/Test-Gateway.ps1` |
| Todo lo medido y decidido | `11-mejoras-y-decisiones.md` |

## 15. Continuación (2026-09-23): NexoDeck como cliente, y lo que sigue

El endpoint de §3 y la autenticación de §10.4b siguen vigentes. Lo que cambió es que los presets de NexoDeck **ya incluyen `custom`**.

- **NexoDeck.** El preset `custom` («Otro (proxy propio)») ahora lo devuelve `nexodeck-ai::remote::presets()`. Antes `CUSTOM_PRESET_ID` estaba definido pero **sin usar**, así que la UI no lo ofrecía (el doc 11, 7.21, daba por hecho que sí). Alta: *proveedor remoto* → **Otro (proxy propio)** → dirección `http://127.0.0.1:8888` (o la del túnel), modelo `auto` (o `router`/`fast`/`complex`), y la clave `ndk_…` que enseña `llm-gateway keys add <cliente>` **una sola vez**. Al guardar, NexoDeck comprueba la clave con `GET /v1/models`, que la pasarela sirve. Verificado a nivel de pasarela (`tools-check.py --model auto`: HTTP 200, llama a la herramienta, sin razonar en voz alta, y con `stream: true` recompone la llamada); el clic en la UI queda a mano, porque no hay automatización de ese diálogo.
- **Los configs de §8 están desactualizados.** Usan `apiKey: "dummy"` y puertos directos (8000-8002), que ya no se publican y no autentican. Hay que reescribirlos a la pasarela: `base_url` `http://localhost:8888/v1`, clave `ndk_…`, y modelos `auto` | `router` | `fast` | `complex` (**no** los nombres de modelo de §8). El autocompletado de Continue puede apuntar a `fast` (Gemma) por la pasarela igual.
- **El túnel de §9 sigue sin probar y aplazado:** el caso de NexoDeck en la misma máquina no lo necesita. Si se hace, recuerda que la pasarela es loopback-only y el túnel va delante (Cloudflare necesita dominio; alternativa Tailscale).
- **Rate limiting y gestión de Sleep Mode desde el cliente:** siguen fuera de alcance (doc 11 §7.17 y `llm-stack/gateway/README.md`).
