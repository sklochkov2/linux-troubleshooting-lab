package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"html/template"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

type cfg struct {
	Listen  string
	BaseURL string
	Prefix  string
	Count   int
	Timeout time.Duration
	Refresh int
}

func getEnv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
func envInt(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

func loadCfg() cfg {
	c := cfg{}
	flag.StringVar(&c.Listen, "listen", getEnv("DASH_LISTEN", "127.0.0.1:8080"), "listen addr")
	flag.StringVar(&c.BaseURL, "base", getEnv("DASH_BASE_URL", "http://127.0.0.1"), "base URL")
	flag.StringVar(&c.Prefix, "prefix", getEnv("DASH_PREFIX", "/api/v1/endpoint"), "endpoint path prefix")
	flag.IntVar(&c.Count, "count", envInt("DASH_COUNT", 4), "number of endpoints (1..N)")
	flag.DurationVar(&c.Timeout, "timeout", func() time.Duration {
		if v := os.Getenv("DASH_TIMEOUT"); v != "" {
			if d, err := time.ParseDuration(v); err == nil {
				return d
			}
		}
		return 1500 * time.Millisecond
	}(), "HTTP timeout (e.g. 1500ms, 2s)")
	flag.IntVar(&c.Refresh, "refresh", envInt("DASH_REFRESH", 3), "HTML auto-refresh seconds (0=off)")
	flag.Parse()
	return c
}

type ProbeResult struct {
	Path      string `json:"path"`
	URL       string `json:"url"`
	Status    string `json:"status"`
	HTTPCode  int    `json:"http_code"`
	Err       string `json:"error,omitempty"`
	CheckedAt string `json:"checked_at"`
}

func probe(client *http.Client, url string) ProbeResult {
	res := ProbeResult{URL: url, CheckedAt: time.Now().Format(time.RFC3339)}
	req, _ := http.NewRequest("GET", url, nil)
	resp, err := client.Do(req)
	if err != nil {
		res.Status = "DOWN"
		res.Err = err.Error()
		return res
	}
	defer resp.Body.Close()
	res.HTTPCode = resp.StatusCode
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		res.Status = "UP"
	} else {
		res.Status = fmt.Sprintf("HTTP %d", resp.StatusCode)
	}
	return res
}

func statusClass(s string) string {
	if s == "UP" {
		return "UP"
	}
	if strings.HasPrefix(s, "HTTP") {
		return "HTTP"
	}
	return "DOWN"
}

var funcMap = template.FuncMap{
	"add":         func(a, b int) int { return a + b },
	"statusClass": statusClass,
}

const pageHTML = `<!doctype html><meta charset="utf-8">
<title>Lab dashboard</title>
{{if .Refresh}}<meta http-equiv="refresh" content="{{.Refresh}}">{{end}}
<style>
body{font:14px system-ui,Arial,sans-serif;margin:24px}
table{border-collapse:collapse;width:100%;max-width:720px}
th,td{border:1px solid #ddd;padding:8px;text-align:left}
th{background:#f3f3f3}
.status-UP{color:#0a0}
.status-DOWN{color:#a00}
.status-HTTP{color:#a60}
small{color:#666}
</style>
<h1>Linux troubleshooting lab</h1>
<p>Probing {{.Count}} endpoints under <code>{{.Base}}{{.Prefix}}1..{{.Count}}</code></p>
<table>
<tr><th>#</th><th>Path</th><th>Status</th><th>HTTP</th><th>Checked</th><th>URL</th></tr>
{{range $i, $r := .Rows}}
<tr>
  <td>{{add $i 1}}</td>
  <td><code>{{$r.Path}}</code></td>
  <td class="status-{{statusClass $r.Status}}">{{$r.Status}}{{if $r.Err}} <small>{{$r.Err}}</small>{{end}}</td>
  <td>{{$r.HTTPCode}}</td>
  <td><small>{{$r.CheckedAt}}</small></td>
  <td><a href="{{$r.URL}}">{{$r.URL}}</a></td>
</tr>
{{end}}
</table>`

var tpl = template.Must(template.New("page").Funcs(funcMap).Parse(pageHTML))

func main() {
	cfg := loadCfg()
	client := &http.Client{Timeout: cfg.Timeout}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		results := make([]ProbeResult, 0, cfg.Count)
		for i := 1; i <= cfg.Count; i++ {
			path := fmt.Sprintf("%s%d", cfg.Prefix, i)
			url := cfg.BaseURL + path
			res := probe(client, url)
			res.Path = path
			results = append(results, res)
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_ = tpl.Execute(w, map[string]any{
			"Rows":    results,
			"Count":   cfg.Count,
			"Base":    cfg.BaseURL,
			"Prefix":  cfg.Prefix,
			"Refresh": cfg.Refresh,
		})
	})

	http.HandleFunc("/api/status", func(w http.ResponseWriter, r *http.Request) {
		results := make([]ProbeResult, 0, cfg.Count)
		for i := 1; i <= cfg.Count; i++ {
			path := fmt.Sprintf("%s%d", cfg.Prefix, i)
			url := cfg.BaseURL + path
			res := probe(client, url)
			res.Path = path
			results = append(results, res)
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(results)
	})

	srv := &http.Server{
		Addr:              cfg.Listen,
		ReadHeaderTimeout: 2 * time.Second,
	}
	if err := srv.ListenAndServe(); err != nil {
		panic(err)
	}
}
