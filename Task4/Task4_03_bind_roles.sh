#!/bin/bash
# =============================================================================
# Task4 — Скрипт 3: Связывание пользователей с ролями (RoleBinding / ClusterRoleBinding)
# PropDevelopment
#
# Стратегия привязки:
#   - Группы (subjects.kind=Group) используются для привязки через O-поле сертификата.
#     Это позволяет добавлять новых пользователей в группу без изменения bindings.
#   - Конкретные пользователи (subjects.kind=User) привязываются для точечного контроля
#     (например, специалист ИБ и platform-admin — поимённо).
#
# Соответствие группа → роль:
#   viewers            → ClusterRole/viewer    (через RoleBinding в каждом NS)
#   developers         → Role/developer        (RoleBinding в своём NS)
#   devops-engineers   → Role/devops-engineer  (RoleBinding в каждом NS)
#   security-auditors  → ClusterRole/security-auditor (ClusterRoleBinding)
#   cluster-admins     → ClusterRole/cluster-admin    (ClusterRoleBinding)
# =============================================================================

set -euo pipefail

echo "======================================================================"
echo "PropDevelopment — Связывание пользователей с ролями RBAC"
echo "======================================================================"

NAMESPACES=("prop-sales" "prop-housing" "prop-finance" "prop-data")

# =============================================================================
# 1. VIEWERS — группа viewers → ClusterRole/viewer
#    Используем RoleBinding в каждом namespace (не ClusterRoleBinding),
#    чтобы ограничить просмотр только namespace компании, а не всего кластера.
# =============================================================================
echo ""
echo "[1] Привязка группы 'viewers' → Role viewer (во всех namespace)..."

for NS in "${NAMESPACES[@]}"; do
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: viewers-binding
  namespace: ${NS}
  labels:
    app.kubernetes.io/managed-by: propdev-rbac
subjects:
  # Привязка через группу — все пользователи с O=viewers в сертификате
  - kind: Group
    name: viewers
    apiGroup: rbac.authorization.k8s.io
  # Явные пользователи (дополнительно к группе)
  - kind: User
    name: ivan-petrov
    apiGroup: rbac.authorization.k8s.io
  - kind: User
    name: anna-smirnova
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole      # Используем ClusterRole, применённую через RoleBinding
  name: viewer
  apiGroup: rbac.authorization.k8s.io
EOF
  echo "  [✓] RoleBinding/viewers-binding в namespace/${NS}"
done

# =============================================================================
# 2. DEVELOPERS — группа developers → Role/developer
#    Каждый разработчик работает в namespace своего домена.
#    Дополнительно: конкретные пользователи привязаны к конкретным namespace.
# =============================================================================
echo ""
echo "[2] Привязка группы 'developers' → Role developer..."

# Группа developers имеет доступ ко всем namespace (общая привязка)
for NS in "${NAMESPACES[@]}"; do
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developers-binding
  namespace: ${NS}
  labels:
    app.kubernetes.io/managed-by: propdev-rbac
subjects:
  - kind: Group
    name: developers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io
EOF
  echo "  [✓] RoleBinding/developers-binding в namespace/${NS}"
done

# Точечная привязка: dmitry-kozlov работает в домене продаж
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dmitry-kozlov-sales
  namespace: prop-sales
  labels:
    app.kubernetes.io/managed-by: propdev-rbac
subjects:
  - kind: User
    name: dmitry-kozlov
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io
EOF
echo "  [✓] RoleBinding/dmitry-kozlov-sales в namespace/prop-sales"

# elena-volkova работает в домене ЖКУ
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: elena-volkova-housing
  namespace: prop-housing
  labels:
    app.kubernetes.io/managed-by: propdev-rbac
subjects:
  - kind: User
    name: elena-volkova
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io
EOF
echo "  [✓] RoleBinding/elena-volkova-housing в namespace/prop-housing"

# =============================================================================
# 3. DEVOPS-ENGINEERS — группа devops-engineers → Role/devops-engineer
#    DevOps-инженеры имеют доступ ко всем namespace (они настраивают инфраструктуру).
# =============================================================================
echo ""
echo "[3] Привязка группы 'devops-engineers' → Role devops-engineer..."

for NS in "${NAMESPACES[@]}"; do
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: devops-engineers-binding
  namespace: ${NS}
  labels:
    app.kubernetes.io/managed-by: propdev-rbac
subjects:
  - kind: Group
    name: devops-engineers
    apiGroup: rbac.authorization.k8s.io
  - kind: User
    name: sergey-novikov
    apiGroup: rbac.authorization.k8s.io
  - kind: User
    name: maria-ivanova
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: devops-engineer
  apiGroup: rbac.authorization.k8s.io
EOF
  echo "  [✓] RoleBinding/devops-engineers-binding в namespace/${NS}"
done

# Также devops-инженеры должны видеть ресурсы в режиме viewer на уровне кластера
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: devops-engineers-cluster-viewer
  labels:
    app.kubernetes.io/managed-by: propdev-rbac
subjects:
  - kind: Group
    name: devops-engineers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: viewer
  apiGroup: rbac.authorization.k8s.io
EOF
echo "  [✓] ClusterRoleBinding/devops-engineers-cluster-viewer (просмотр nodes)"

# =============================================================================
# 4. SECURITY-AUDITORS — ClusterRoleBinding на весь кластер
#    Специалист по ИБ должен видеть все namespace и секреты.
#    Это осознанное решение: аудит требует полного доступа на чтение.
# =============================================================================
echo ""
echo "[4] Привязка группы 'security-auditors' → ClusterRole security-auditor..."

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: security-auditors-binding
  labels:
    app.kubernetes.io/managed-by: propdev-rbac
    propdev.io/note: "privileged-role-security-only"
subjects:
  - kind: Group
    name: security-auditors
    apiGroup: rbac.authorization.k8s.io
  - kind: User
    name: alexey-morozov    # Единственный специалист по ИБ в PropDevelopment
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: security-auditor
  apiGroup: rbac.authorization.k8s.io
EOF
echo "  [✓] ClusterRoleBinding/security-auditors-binding"

# =============================================================================
# 5. CLUSTER-ADMINS — ClusterRoleBinding, встроенная роль cluster-admin
#    Строго ограничено: только platform-admin (не более 2 человек в компании).
#    Используем поимённую привязку (не группу), чтобы исключить случайное
#    добавление в группу cluster-admins нового пользователя.
# =============================================================================
echo ""
echo "[5] Привязка пользователя 'platform-admin' → ClusterRole cluster-admin..."

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-admins-binding
  labels:
    app.kubernetes.io/managed-by: propdev-rbac
    propdev.io/note: "critical-change-requires-security-approval"
subjects:
  # Поимённая привязка (не через группу) для максимального контроля
  - kind: User
    name: platform-admin
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF
echo "  [✓] ClusterRoleBinding/cluster-admins-binding"

# =============================================================================
# Итоговая проверка
# =============================================================================
echo ""
echo "======================================================================"
echo "Все привязки созданы!"
echo ""
echo "Проверка ClusterRoleBindings:"
kubectl get clusterrolebindings | grep -E "security-auditors|cluster-admins|devops-engineers-cluster"

echo ""
echo "Проверка RoleBindings в namespace prop-sales:"
kubectl get rolebindings -n prop-sales

echo ""
echo "--- Тест доступа (примеры) ---"
echo "Тест viewer (ivan-petrov) в prop-sales:"
kubectl auth can-i list pods \
  --namespace=prop-sales \
  --as=ivan-petrov \
  --as-group=viewers

echo "Тест viewer (ivan-petrov) — попытка создать pod (должен быть ОТКАЗ):"
kubectl auth can-i create pods \
  --namespace=prop-sales \
  --as=ivan-petrov \
  --as-group=viewers

echo "Тест developer (dmitry-kozlov) — создать deployment в prop-sales:"
kubectl auth can-i create deployments \
  --namespace=prop-sales \
  --as=dmitry-kozlov \
  --as-group=developers

echo "Тест developer (dmitry-kozlov) — прочитать secret (должен быть ОТКАЗ):"
kubectl auth can-i get secrets \
  --namespace=prop-sales \
  --as=dmitry-kozlov \
  --as-group=developers

echo "Тест security-auditor (alexey-morozov) — читать secrets:"
kubectl auth can-i get secrets \
  --namespace=prop-sales \
  --as=alexey-morozov \
  --as-group=security-auditors

echo "Тест security-auditor (alexey-morozov) — попытка удалить pod (должен быть ОТКАЗ):"
kubectl auth can-i delete pods \
  --namespace=prop-sales \
  --as=alexey-morozov \
  --as-group=security-auditors

echo "Тест platform-admin — полный доступ:"
kubectl auth can-i '*' '*' \
  --as=platform-admin

echo ""
echo "======================================================================"
echo "Готово! Ролевая модель PropDevelopment настроена."
echo ""
echo "Итоговая схема доступа:"
echo "  viewers            → просмотр ресурсов (без secrets) во всех NS"
echo "  developers         → управление workloads (без secrets) в своём NS"
echo "  devops-engineers   → полная настройка NS + чтение secrets в своём NS"
echo "  security-auditors  → чтение ВСЕГО кластера включая secrets (аудит)"
echo "  cluster-admins     → полный доступ (только platform-admin)"
echo "======================================================================"
