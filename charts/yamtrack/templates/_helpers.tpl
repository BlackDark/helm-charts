{{/*
Expand the name of the chart.
*/}}
{{- define "yamtrack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "yamtrack.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "yamtrack.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "yamtrack.labels" -}}
helm.sh/chart: {{ include "yamtrack.chart" . }}
{{ include "yamtrack.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "yamtrack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "yamtrack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "yamtrack.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "yamtrack.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Secret holding Django SECRET
*/}}
{{- define "yamtrack.secretName" -}}
{{- if .Values.secret.existingSecret }}
{{- .Values.secret.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "yamtrack.fullname" .) }}
{{- end }}
{{- end }}

{{/*
PVC name
*/}}
{{- define "yamtrack.pvcName" -}}
{{- if .Values.persistence.existingClaim }}
{{- .Values.persistence.existingClaim }}
{{- else }}
{{- printf "%s-data" (include "yamtrack.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Fail fast on missing required config.
*/}}
{{- define "yamtrack.validate" -}}
{{- if and (not .Values.redis.url) (not .Values.redis.existingSecret) }}
{{- fail "Yamtrack requires Redis. Set redis.url or redis.existingSecret." }}
{{- end }}
{{- if and (not .Values.secret.create) (not .Values.secret.existingSecret) }}
{{- fail "Set secret.create=true or secret.existingSecret for Django SECRET." }}
{{- end }}
{{- $forbidden := dict "SECRET" true "REDIS_URL" true "CELERY_REDIS_URL" true "DB_PASSWORD" true }}
{{- range $key, $_ := .Values.config }}
{{- if hasKey $forbidden $key }}
{{- fail (printf "config.%s belongs in secret/redis/postgresql, not ConfigMap." $key) }}
{{- end }}
{{- end }}
{{- if and .Values.persistence.enabled (eq .Values.persistence.accessMode "ReadWriteOnce") (gt (int .Values.replicaCount) 1) }}
{{- fail "replicaCount > 1 requires persistence.accessMode=ReadWriteMany or persistence.enabled=false." }}
{{- end }}
{{- if and .Values.persistence.enabled (eq .Values.persistence.accessMode "ReadWriteOnce") (ne .Values.updateStrategy.type "Recreate") }}
{{- fail "ReadWriteOnce persistence requires updateStrategy.type=Recreate." }}
{{- end }}
{{- if .Values.postgresql.enabled }}
{{- if not .Values.postgresql.host }}
{{- fail "postgresql.enabled=true requires postgresql.host." }}
{{- end }}
{{- if not .Values.postgresql.existingSecret }}
{{- fail "postgresql.enabled=true requires postgresql.existingSecret for DB_PASSWORD." }}
{{- end }}
{{- end }}
{{- if .Values.networkPolicy.enabled }}
{{- if not .Values.networkPolicy.redis.podSelector }}
{{- fail "networkPolicy.enabled=true requires networkPolicy.redis.podSelector." }}
{{- end }}
{{- if and .Values.postgresql.enabled (not .Values.networkPolicy.postgres.podSelector) }}
{{- fail "networkPolicy.enabled with postgresql.enabled requires networkPolicy.postgres.podSelector." }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Application environment (secrets + structured settings).
*/}}
{{- define "yamtrack.env" -}}
- name: SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "yamtrack.secretName" . }}
      key: {{ .Values.secret.existingSecretKey | quote }}
{{- if .Values.redis.existingSecret }}
- name: REDIS_URL
  valueFrom:
    secretKeyRef:
      name: {{ .Values.redis.existingSecret | quote }}
      key: {{ .Values.redis.existingSecretKey | quote }}
{{- else if .Values.redis.url }}
- name: REDIS_URL
  value: {{ .Values.redis.url | quote }}
{{- end }}
{{- if .Values.postgresql.enabled }}
- name: DB_HOST
  value: {{ .Values.postgresql.host | quote }}
- name: DB_PORT
  value: {{ .Values.postgresql.port | quote }}
- name: DB_NAME
  value: {{ .Values.postgresql.database | quote }}
- name: DB_USER
  value: {{ .Values.postgresql.user | quote }}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresql.existingSecret | quote }}
      key: {{ .Values.postgresql.existingSecretPasswordKey | quote }}
{{- range $key, $value := .Values.postgresql.extraConfig }}
- name: {{ $key }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}
{{- range .Values.extraEnv }}
- name: {{ .name }}
  {{- if .value }}
  value: {{ .value | quote }}
  {{- else if .valueFrom }}
  valueFrom:
    {{- toYaml .valueFrom | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}
