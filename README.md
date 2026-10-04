# Kubernetes: Nginx, Gateway API, Prometheus и Filebeat

Одноузловой Kubernetes-кластер на Ubuntu 24.04, установленный через kubeadm.
Приложение Nginx возвращает `Hello world!`; доступ организован через Gateway API.
Prometheus собирает метрики контроллера Gateway, Filebeat сохраняет access/error-логи приложения.

## Архитектура

```text
HTTP-клиент
  -> NodePort
  -> NGINX Gateway Fabric
  -> HTTPRoute nginx-route
  -> Service nginx-service
  -> Pod Nginx: Hello world!

Prometheus -> метрики контроллера Gateway, порт 9113
Filebeat   -> контейнерные логи Nginx -> JSON-файлы на узле
```

Узел совмещает control plane и выполнение приложений. Flannel обеспечивает сеть Pod.
HTML и конфигурация приложения передаются через ConfigMap `nginx-files`.

| Namespace | Компоненты |
|---|---|
| `nginx` | Nginx, Service приложения, Gateway, HTTPRoute и прокси Gateway |
| `nginx-gateway` | Контроллер NGINX Gateway Fabric |
| `monitoring` | Prometheus |
| `logging` | Filebeat DaemonSet |

## Компоненты

| Компонент | Версия |
|---|---|
| Kubernetes через kubeadm | 1.37.1 |
| containerd на исходном стенде | 2.2.1 |
| Flannel | 0.28.9 |
| Nginx приложения | 1.30.5 |
| NGINX Gateway Fabric | 2.7.2 |
| Gateway API CRD | 1.6.1 |
| Prometheus | 3.15.0 |
| Filebeat | 9.5.4 |

Испытания выполнены на Ubuntu 24.04 ARM64 в VirtualBox. Исходный стенд:
Ubuntu 24.04.5 LTS, 4 vCPU, около 8 GiB RAM.
Точные версии APT-пакетов пока не закреплены: скрипт устанавливает пакеты из настроенных репозиториев.
Конфигурация containerd в `prepare.sh` рассчитана на containerd 2.x.

## Структура

```text
scripts/
  prepare.sh      # Подготовка ОС и создание кластера
  deploy.sh       # Nginx: генерация и применение манифестов
  gateway.sh      # Gateway Controller, CRD, Gateway и HTTPRoute
  monitoring.sh  # Prometheus
  logging.sh     # Filebeat
  deploy-app.sh  # Последовательный запуск четырех компонентов
kubernetes/      # Namespace приложения
nginx/           # ConfigMap, Deployment и Service
gateway/         # Gateway API
monitoring/      # Prometheus и PV/PVC
logging/         # Filebeat
```

## Установка на чистой Ubuntu 24.04

Команды выполнять в Ubuntu обычным пользователем с правами sudo.
Требуется доступ к APT-репозиториям, GitHub и реестрам контейнерных образов.
Все последующие команды выполнять из корня репозитория. Используется Bash, а не `sh`.

```bash
sudo apt-get update
sudo apt-get install -y git curl python3
git clone --branch master https://github.com/timur0o31/k8s-task.git
cd k8s-task
```


### Кластер и компоненты

```bash
bash scripts/prepare.sh
kubectl wait --for=condition=Ready node --all --timeout=180s
bash scripts/deploy-app.sh
kubectl get nodes
kubectl get pods -A
```

Ожидается узел `Ready` и готовность основных Pod `1/1`.
`prepare.sh` пропускает `kubeadm init`, если существует `/etc/kubernetes/admin.conf`.
`deploy-app.sh` автоматически разворачивает приложение, Gateway API, мониторинг и логирование.
Не требуется вручную создавать или редактировать Kubernetes-ресурсы.

## Проверка Gateway API и приложения

Реализация: **NGINX Gateway Fabric 2.7.2**. Используются:

- GatewayClass `nginx`;
- Gateway `nginx/web-gateway`, HTTP listener на порту 80;
- HTTPRoute `nginx/nginx-route`, путь `/`;
- backend Service `nginx/nginx-service`, порт 80.

Разрешено подключать HTTPRoute из того же namespace, что и Gateway (`from: Same`).

Gateway получает NodePort автоматически. Определить фактический адрес и проверить ответ:

```bash
NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
GATEWAY_PORT="$(kubectl get service web-gateway-nginx -n nginx -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')"
GATEWAY_URL="http://${NODE_IP}:${GATEWAY_PORT}"
curl -fsS -i --max-time 10 "${GATEWAY_URL}/"
```

Ожидается HTTP `200 OK` и тело `Hello world!`.
На новой VM проверен адрес `http://10.0.2.15:32085/`; при другой установке порт может отличаться.
Проверка выполняется в Ubuntu. Для доступа из macOS к VM с NAT требуется отдельно
пробросить порт в VirtualBox.

## Проверка Prometheus

Prometheus собирает метрики каждые 15 секунд:

```text
job: nginx-gateway
target: nginx-gateway.nginx-gateway.svc.cluster.local:9113
path: /metrics
```

Основные запросы:

| Запрос | Что проверяет |
|---|---|
| `up{job="nginx-gateway"}` | Успешность сбора метрик; ожидается `1` |
| `go_goroutines{job="nginx-gateway"}` | Число горутин контроллера |
| `process_resident_memory_bytes{job="nginx-gateway"}` | Резидентная память процесса в байтах |

Проверка через API Prometheus из Pod приложения:

```bash
kubectl exec -n nginx deployment/nginx-deployment -- \
  curl -fsS -G --max-time 10 \
  http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query \
  --data-urlencode 'query=up{job="nginx-gateway"}'

kubectl exec -n nginx deployment/nginx-deployment -- \
  curl -fsS -G --max-time 10 \
  http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query \
  --data-urlencode 'query=go_goroutines{job="nginx-gateway"}'
```

Ожидается `status: success` и непустой результат. Для `up` значение должно быть `1`.
Проверка состояния target:

```bash
kubectl exec -n nginx deployment/nginx-deployment -- \
  curl -fsS --max-time 10 \
  http://prometheus.monitoring.svc.cluster.local:9090/api/v1/targets \
  | python3 -m json.tool
```

У target `nginx-gateway` ожидается `health: up`, пустой `lastError`.

Для интерфейса Prometheus выполнить в отдельном терминале Ubuntu:

```bash
kubectl port-forward -n monitoring service/prometheus 9090:9090
```

После этого интерфейс доступен на `http://127.0.0.1:9090/` внутри Ubuntu.
Переадресация действует, пока команда работает. Для браузера macOS нужен SSH-туннель
или дополнительный проброс порта. После пересоздания Pod переадресацию нужно запустить заново.

## Проверка Filebeat

Nginx пишет access-логи в stdout, error-логи в stderr.
Filebeat читает CRI-логи приложения из `/var/log/containers/nginx-deployment-*_nginx_nginx-*.log`
и сохраняет JSON-события в `/var/log/k8s-task/filebeat/nginx*` на узле.

После определения `GATEWAY_URL` в разделе проверки Gateway выполнить:

```bash
CHECK="check-$(date +%s)"
curl -fsS -i --max-time 10 "${GATEWAY_URL}/?check=${CHECK}"
curl -sS -i --max-time 10 "${GATEWAY_URL}/missing-${CHECK}"
sudo grep -F "$CHECK" /var/log/k8s-task/filebeat/nginx*
```

Ожидаются:

- успешный ответ `200` и соответствующий access-лог (`stream: stdout`);
- ответ `404` и соответствующий access-лог (`stream: stdout`);
- error-лог отсутствующего файла (`stream: stderr`).

Сбор асинхронный: если поиск пока ничего не нашел, повторить его через несколько секунд.
Уникальный маркер позволяет отличить новый запрос от старых событий.

## Повторный запуск

Повторное применение ресурсов выполняется через `kubectl apply`.
На исходном стенде успешно проверены повторные запуски всех четырех скриптов компонентов:
приложения, Gateway, Prometheus и Filebeat. После повторных запусков приложение отвечало,
Prometheus возвращал `up=1`, новый HTTP-запрос появлялся в собранных логах.

```bash
bash scripts/deploy-app.sh
```

После повторного запуска снова выполнить проверки Gateway, Prometheus и Filebeat.
Повторное выполнение `prepare.sh` пока отдельно не проверено. Наличие `admin.conf`
предотвращает повторный `init`, но само по себе не подтверждает исправность кластера.
Скрипты не выполняют `kubeadm reset` и не удаляют данные.

`deploy.sh` генерирует манифесты Nginx заново; изменения этих ресурсов нужно вносить в скрипт.
`gateway.sh` использует существующий `gateway/gateway.yaml`, если файл уже есть.
Prometheus включает автоматическую перезагрузку конфигурации.
Если меняется ConfigMap Filebeat, его файл смонтирован через `subPath`; требуется перезапуск:

```bash
kubectl rollout restart daemonset/filebeat -n logging
kubectl rollout status daemonset/filebeat -n logging --timeout=180s
```

## Хранение и ограничения

- Один узел: высокая доступность не обеспечивается.
- Используется HTTP без TLS.
- Данные Prometheus: `/var/lib/k8s-task/prometheus`, PV/PVC `prometheus-data`, политика `Retain`.
  Retention - 7 дней, ограничение TSDB - 1 GB. Заявленные 2 GiB PV не являются квотой hostPath.
- Логи Filebeat: `/var/log/k8s-task/filebeat`; ротация файлов около 10 MiB, настройка `number_of_files: 7`.
- Registry Filebeat: `/var/lib/k8s-task/filebeat`; сохранение позволяет продолжать чтение после перезапуска.
- Данные расположены на узле; удаление виртуального диска приводит к их потере.
- Мониторинг собирает метрики контроллера Gateway. Отдельный exporter HTTP-метрик приложения не настроен.
- Точные версии APT-пакетов не закреплены; внешние репозитории необходимы для установки.
- CI/CD не настроен.

## Результаты

На новой VM после чистой установки Ubuntu 24.04 подтверждены:

- узел Kubernetes 1.37.1 в состоянии `Ready`;
- все Pod основных компонентов `Running`, готовность `1/1`, без перезапусков на момент проверки;
- ответ через Gateway API: `200 OK`, `Hello world!`;
- Prometheus query `up{job="nginx-gateway"}` со значением `1`;
- сбор нового access-лога с маркером `fresh-install-1791145608`;
- сбор access/error-логов запроса `/missing-fresh-install-1791145608`.

На исходной установке дополнительно подтверждены реальная метрика `go_goroutines`
и работоспособность после повторных запусков четырех скриптов компонентов.
Полный повторный запуск подготовки ОС и кластера, а также перезагрузка нового стенда
отдельно проверены.

## Диагностика

```bash
kubectl get nodes
kubectl get pods -A
kubectl get gateway,httproute -n nginx
kubectl describe gateway web-gateway -n nginx
kubectl get pv prometheus-data
kubectl get pvc prometheus-data -n monitoring
kubectl logs -n nginx deployment/nginx-deployment --tail=30
kubectl logs -n monitoring deployment/prometheus -c prometheus --tail=30
kubectl logs -n logging daemonset/filebeat --tail=30
```
