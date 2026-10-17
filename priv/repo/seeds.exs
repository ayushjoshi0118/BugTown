alias BugTown.Repo
alias BugTown.Topology.{Service, ServiceDependency}
alias BugTown.Experiments.Experiment
import Ecto.Query

services_data = [
  %{
    name: "API Gateway",
    slug: "api-gateway",
    category: "gateway",
    status: "healthy",
    baseline_latency_ms: 12,
    baseline_error_rate: 0.001,
    baseline_cpu: 24.5,
    baseline_memory_mb: 320,
    pos_x: 450,
    pos_y: 70,
    metadata: %{
      "description" => "Edge routing, TLS termination, global rate limiting, and JWT validation.",
      "rps_capacity" => 5000,
      "tech" => "Elixir / Phoenix"
    }
  },
  %{
    name: "Authentication Service",
    slug: "auth-service",
    category: "service",
    status: "healthy",
    baseline_latency_ms: 18,
    baseline_error_rate: 0.002,
    baseline_cpu: 18.2,
    baseline_memory_mb: 256,
    pos_x: 230,
    pos_y: 190,
    metadata: %{
      "description" => "Session validation, OAuth2 tokens, and role-based access control.",
      "rps_capacity" => 2500,
      "tech" => "Go / gRPC"
    }
  },
  %{
    name: "Order Service",
    slug: "order-service",
    category: "service",
    status: "healthy",
    baseline_latency_ms: 35,
    baseline_error_rate: 0.003,
    baseline_cpu: 32.0,
    baseline_memory_mb: 480,
    pos_x: 670,
    pos_y: 190,
    metadata: %{
      "description" => "Checkout orchestration, order lifecycle, and fulfillment coordination.",
      "rps_capacity" => 1800,
      "tech" => "Node.js / Express"
    }
  },
  %{
    name: "User Service",
    slug: "user-service",
    category: "service",
    status: "healthy",
    baseline_latency_ms: 22,
    baseline_error_rate: 0.001,
    baseline_cpu: 16.5,
    baseline_memory_mb: 384,
    pos_x: 230,
    pos_y: 310,
    metadata: %{
      "description" => "User profiles, preferences, billing identities, and KYC state.",
      "rps_capacity" => 3000,
      "tech" => "Rust / Axum"
    }
  },
  %{
    name: "Redis Cache",
    slug: "redis-cache",
    category: "cache",
    status: "healthy",
    baseline_latency_ms: 2,
    baseline_error_rate: 0.0001,
    baseline_cpu: 8.0,
    baseline_memory_mb: 512,
    pos_x: 70,
    pos_y: 310,
    metadata: %{
      "description" =>
        "In-memory distributed cache for sessions, user metadata, and hot query keys.",
      "rps_capacity" => 25000,
      "tech" => "Redis 7.2"
    }
  },
  %{
    name: "Inventory Service",
    slug: "inventory-service",
    category: "service",
    status: "healthy",
    baseline_latency_ms: 28,
    baseline_error_rate: 0.002,
    baseline_cpu: 21.0,
    baseline_memory_mb: 340,
    pos_x: 530,
    pos_y: 310,
    metadata: %{
      "description" => "Warehouse SKU reservations, stock allocation, and catalog availability.",
      "rps_capacity" => 2200,
      "tech" => "Python / FastAPI"
    }
  },
  %{
    name: "Payment Service",
    slug: "payment-service",
    category: "service",
    status: "healthy",
    baseline_latency_ms: 65,
    baseline_error_rate: 0.004,
    baseline_cpu: 29.5,
    baseline_memory_mb: 420,
    pos_x: 810,
    pos_y: 310,
    metadata: %{
      "description" => "Payment tokenization, gateway settlements, anti-fraud checks.",
      "rps_capacity" => 1200,
      "tech" => "Java / Spring Boot"
    }
  },
  %{
    name: "PostgreSQL Database",
    slug: "postgres-db",
    category: "database",
    status: "healthy",
    baseline_latency_ms: 8,
    baseline_error_rate: 0.0005,
    baseline_cpu: 35.0,
    baseline_memory_mb: 1024,
    pos_x: 230,
    pos_y: 450,
    metadata: %{
      "description" =>
        "Simulated primary relational store with ACID transactions and connection pool.",
      "rps_capacity" => 4000,
      "tech" => "PostgreSQL 16"
    }
  },
  %{
    name: "Message Queue",
    slug: "message-queue",
    category: "queue",
    status: "healthy",
    baseline_latency_ms: 4,
    baseline_error_rate: 0.0002,
    baseline_cpu: 12.0,
    baseline_memory_mb: 512,
    pos_x: 530,
    pos_y: 450,
    metadata: %{
      "description" => "Durable pub/sub event bus for async order events and notifications.",
      "rps_capacity" => 15000,
      "tech" => "Apache Kafka / RabbitMQ"
    }
  },
  %{
    name: "Notification Worker",
    slug: "notification-worker",
    category: "worker",
    status: "healthy",
    baseline_latency_ms: 45,
    baseline_error_rate: 0.005,
    baseline_cpu: 14.0,
    baseline_memory_mb: 280,
    pos_x: 810,
    pos_y: 450,
    metadata: %{
      "description" => "Async email, SMS, and webhook delivery worker consuming from queue.",
      "rps_capacity" => 800,
      "tech" => "Go Consumer"
    }
  }
]

# Insert or update services
created_services =
  Enum.map(services_data, fn data ->
    case Repo.get_by(Service, slug: data.slug) do
      nil ->
        %Service{}
        |> Service.changeset(data)
        |> Repo.insert!()

      existing ->
        existing
        |> Service.changeset(data)
        |> Repo.update!()
    end
  end)
  |> Map.new(fn s -> {s.slug, s} end)

# Dependencies data
dependencies_data = [
  {"api-gateway", "auth-service", "http", 8, true},
  {"api-gateway", "order-service", "http", 15, true},
  {"auth-service", "user-service", "grpc", 10, true},
  {"user-service", "postgres-db", "sql", 6, true},
  {"user-service", "redis-cache", "tcp", 2, false},
  {"order-service", "payment-service", "http", 25, true},
  {"order-service", "inventory-service", "grpc", 14, true},
  {"order-service", "message-queue", "tcp", 4, false},
  {"message-queue", "notification-worker", "tcp", 12, false},
  {"payment-service", "postgres-db", "sql", 8, true},
  {"inventory-service", "postgres-db", "sql", 7, true}
]

Enum.each(dependencies_data, fn {src_slug, tgt_slug, proto, lat, crit} ->
  src = Map.fetch!(created_services, src_slug)
  tgt = Map.fetch!(created_services, tgt_slug)

  case Repo.get_by(ServiceDependency, source_service_id: src.id, target_service_id: tgt.id) do
    nil ->
      %ServiceDependency{}
      |> ServiceDependency.changeset(%{
        source_service_id: src.id,
        target_service_id: tgt.id,
        protocol: proto,
        latency_ms: lat,
        critical: crit
      })
      |> Repo.insert!()

    existing ->
      existing
      |> ServiceDependency.changeset(%{
        protocol: proto,
        latency_ms: lat,
        critical: crit
      })
      |> Repo.update!()
  end
end)

# Seed an initial baseline experiment if none exists
if Repo.aggregate(Experiment, :count) == 0 do
  now = DateTime.utc_now() |> DateTime.truncate(:second)

  %Experiment{}
  |> Experiment.changeset(%{
    name: "Baseline Health & Throughput Benchmark",
    scenario_type: "baseline_health",
    description:
      "Evaluates standard steady-state operational parameters across all 10 core topology services under 120 req/s load.",
    seed: 42,
    status: "completed",
    fault_config: %{},
    recovery_config: %{},
    metrics_summary: %{
      "avg_latency_ms" => 28.4,
      "p95_latency_ms" => 64.2,
      "error_rate_pct" => 0.08,
      "availability_pct" => 99.94,
      "total_requests" => 7200,
      "failed_requests" => 6
    },
    duration_seconds: 60,
    started_at: DateTime.add(now, -3600, :second),
    completed_at: DateTime.add(now, -3540, :second)
  })
  |> Repo.insert!()

  %Experiment{}
  |> Experiment.changeset(%{
    name: "Circuit Breaker Cascade Prevention",
    scenario_type: "circuit_breaker",
    description:
      "Injected simulated database connection failure. Tested circuit breaker trip on Order Service to isolate payment cascade.",
    seed: 1337,
    status: "completed",
    fault_config: %{
      "fault_type" => "database_failure",
      "target_service" => "postgres-db",
      "mode" => "pool_exhaustion"
    },
    recovery_config: %{
      "action" => "circuit_breaker",
      "target_service" => "order-service",
      "threshold" => 5
    },
    metrics_summary: %{
      "before_error_rate_pct" => 78.4,
      "after_error_rate_pct" => 2.1,
      "recovery_time_seconds" => 4.2,
      "availability_pct" => 97.9,
      "mitigation_effective" => true
    },
    duration_seconds: 90,
    started_at: DateTime.add(now, -1800, :second),
    completed_at: DateTime.add(now, -1710, :second)
  })
  |> Repo.insert!()
end

IO.puts(
  "✓ BugTown seed successfully loaded: 10 services, 11 dependencies, baseline experiments initialized."
)
