{{- define "splunk.labels" -}}
app.kubernetes.io/name: splunk
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end }}

{{- define "splunk.selectorLabels" -}}
app: splunk
{{- end }}
