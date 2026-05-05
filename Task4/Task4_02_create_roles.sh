#!/bin/bash
# =============================================================================
# Task4 — Скрипт 2: Создание ролей RBAC в Kubernetes
# PropDevelopment
#
# Создаются:
#   - ClusterRole: viewer, security-auditor, cluster-admin (уже встроен)
#   - Role (namespace-scoped): developer, devops-engineer
#     применяются в каждом namespace домена PropDevelopment
#
# Namespace компании:
#   - prop-sales      (группа сервисов для клиентов)
#   - prop-housing    (группа сервисов ЖКУ)
#   - prop-finance    (финансы)
#   - prop-data       (data-платформа)
# =============================================================================

set -euo pipefail

echo "======================================================================"
echo "PropDevelopment — Создание ролей RBAC"
echo "======================================================================"

# =============================================================================
# Шаг 0: Создание namespace для каждого домена компании
# =============================================================================
echo ""
echo "[0] Создание namespace для доменов PropDevelopment..."

for NS in prop-sales prop-housing prop-finance prop-data; do
  kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f - 
  echo "  [✓] namespace/${NS}"
done

# =============================================================================
# Шаг 1: ClusterRole — viewer
# Только чтение базовых ресурсов кластера. Без доступа к секретам.
# ClusterRole, но используется через RoleBinding (в конкретных namespace)
# и через ClusterRoleBinding (для аналитиков с доступом ко всему кластеру).
# =============================================================================
echo ""
echo "[1] Создание ClusterRole: viewer..."

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: viewer
  labels:
    app.kubernetes.io/managed-by: propdev-rbac
    propdev.io/role-type: "read-only"
rules:
  # Основные workload-ресурсы — только чтение
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - services
      - endpoints
      - configmaps
      - events
      - persistentvolumeclaims
      - resourcequotas
      - limitranges
      - serviceaccounts
    verbs: ["get", "list", "watch"]

  # Workload controllers — только чтение
  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
      - statefulsets
      - daemonsets
    verbs: ["get", "list", "watch"]

  # Batch — только чтение
  - apiGroups: ["batch"]
    resources:
      - jobs
      - cronjobs
    verbs: ["get", "list", "watch"]

  # Networking — только чтение
  - apiGroups: ["networking.k8s.io"]
    resources:
      - ingresses
    verbs: ["get", "list", "watch"]

  # HPA — только чтение
  - apiGroups: ["autoscaling"]
    resources:
      - horizontalpodautoscalers
    verbs: ["get", "list", "watch"]

  # ЗАПРЕЩЕНО (не указано = запрещено в Kubernetes RBAC):
  # - secrets (критично для ИБ PropDevelopment)
  # - nodes
  # - clusterroles / clusterrolebindings
  # - namespaces (управление)
EOF
echo "  [✓] ClusterRole/viewer создана"

# =============================================================================
# Шаг 2: Role — developer (применяется в каждом namespace домена)
# Может деплоить и управлять своими сервисами. Без доступа к секретам.
# =============================================================================
echo ""
echo "[2] Создание Role: developer (во всех namespace доменов)..."

for NS in prop-sales prop-housing prop-finance prop-data; do
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer
  namespace: ${NS}
  labels:
    app.kubernetes.io/managed-by: propdev-rbac
    propdev.io/role-type: "developer"
rules:
  # Pods — полное управление (деплой, перезапуск, логи)
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/exec"]
    verbs: ["get", "list", "watch", "create", "delete"]

  # ConfigMaps — создание и обновление конфигурации (без секретов)
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]

  # Services и endpoints — регистрация сервисов
  - apiGroups: [""]
    resources: ["services", "endpoints"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]

  # Events — мониторинг событий своего namespace
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "list", "watch"]

  # PVC — создание заявок на хранилище
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "create"]

  # Deployments — полное управление деплойментами
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # StatefulSets — для БД-контейнеров (PostgreSQL, MSSQL в dev-окружении)
  - apiGroups: ["apps"]
    resources: ["statefulsets"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]

  # Jobs/CronJobs — batch-задачи (ETL в data-домене)
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # HPA — масштабирование
  - apiGroups: ["autoscaling"]
    resources: ["horizontalpodautoscalers"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]

  # ЗАПРЕЩЕНО:
  # - secrets (разработчик не должен читать prod-секреты)
  # - ingresses (управление роутингом — только devops)
  # - namespaces
  # - clusterroles
EOF
  echo "  [✓] Role/developer в namespace/${NS}"
done

# =============================================================================
# Шаг 3: Role — devops-engineer (namespace-scoped, применяется в каждом NS)
# Может настраивать инфраструктуру своего домена. Читает секреты своего NS.
# =============================================================================
echo ""
echo "[3] Создание Role: devops-engineer (во всех namespace доменов)..."

for NS in prop-sales prop-housing prop-finance prop-data; do
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: devops-engineer
  namespace: ${NS}
  labels:
    app.kubernetes.io/managed-by: propdev-rbac
    propdev.io/role-type: "devops"
rules:
  # Все права developer плюс расширенные

  # Pods — полное управление
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/exec", "pods/portforward"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # ConfigMaps — полное управление
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # Secrets — только чтение в своём namespace (для диагностики)
  # DevOps читает, но не создаёт/изменяет prod-секреты напрямую
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "watch"]

  # Services — полное управление
  - apiGroups: [""]
    resources: ["services", "endpoints"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # PVC — полное управление
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # Events, ResourceQuotas
  - apiGroups: [""]
    resources: ["events", "resourcequotas", "limitranges"]
    verbs: ["get", "list", "watch"]

  # ServiceAccounts — управление в своём namespace
  - apiGroups: [""]
    resources: ["serviceaccounts"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]

  # Workload controllers — полное управление
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # Batch
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # Ingress — управление роутингом
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses", "networkpolicies"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # HPA — управление масштабированием
  - apiGroups: ["autoscaling"]
    resources: ["horizontalpodautoscalers"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

  # RBAC внутри namespace — для назначения ServiceAccount ролей
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings"]
    verbs: ["get", "list", "watch"]

  # ЗАПРЕЩЕНО:
  # - clusterroles / clusterrolebindings (только cluster-admin)
  # - nodes (только cluster-admin)
  # - namespaces (только cluster-admin)
EOF
  echo "  [✓] Role/devops-engineer в namespace/${NS}"
done

# =============================================================================
# Шаг 4: ClusterRole — security-auditor
# Специалист по ИБ: читает всё, включая секреты. Ничего не изменяет.
# Это привилегированная роль с доступом ко всему кластеру.
# =============================================================================
echo ""
echo "[4] Создание ClusterRole: security-auditor..."

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: security-auditor
  labels:
    app.kubernetes.io/managed-by: propdev-rbac
    propdev.io/role-type: "privileged-read"
rules:
  # Полный доступ на чтение ко ВСЕМ ресурсам кластера
  # включая secrets, clusterroles, networkpolicies

  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - services
      - endpoints
      - configmaps
      - secrets        # Ключевое отличие от viewer — доступ к секретам
      - namespaces
      - nodes
      - persistentvolumes
      - persistentvolumeclaims
      - serviceaccounts
      - resourcequotas
      - events
    verbs: ["get", "list", "watch"]

  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
      - statefulsets
      - daemonsets
    verbs: ["get", "list", "watch"]

  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch"]

  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses", "networkpolicies"]
    verbs: ["get", "list", "watch"]

  # RBAC — аудит ролей и привязок (ключевое для ИБ)
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources:
      - roles
      - rolebindings
      - clusterroles
      - clusterrolebindings
    verbs: ["get", "list", "watch"]

  # Policy
  - apiGroups: ["policy"]
    resources: ["podsecuritypolicies", "poddisruptionbudgets"]
    verbs: ["get", "list", "watch"]

  # Autoscaling
  - apiGroups: ["autoscaling"]
    resources: ["horizontalpodautoscalers"]
    verbs: ["get", "list", "watch"]

  # ЗАПРЕЩЕНО (только чтение — никаких изменений):
  # Любые verbs: create, update, patch, delete — не указаны = запрещены
EOF
echo "  [✓] ClusterRole/security-auditor создана"

# =============================================================================
# Шаг 5: Встроенная ClusterRole cluster-admin уже существует в Kubernetes.
# Мы её не пересоздаём, только фиксируем факт использования.
# =============================================================================
echo ""
echo "[5] ClusterRole/cluster-admin — встроенная роль Kubernetes."
echo "    Будет привязана к группе cluster-admins в скрипте 03_bind_roles.sh"
echo "  [✓] Пропускаем создание (уже существует)"

echo ""
echo "======================================================================"
echo "Все роли созданы успешно!"
echo ""
echo "Итог:"
echo "  ClusterRole: viewer, security-auditor (+ встроенная cluster-admin)"
echo "  Role/developer:       prop-sales, prop-housing, prop-finance, prop-data"
echo "  Role/devops-engineer: prop-sales, prop-housing, prop-finance, prop-data"
echo ""
echo "Проверка:"
echo "  kubectl get clusterroles | grep -E 'viewer|security-auditor'"
echo "  kubectl get roles -n prop-sales"
echo "======================================================================"
