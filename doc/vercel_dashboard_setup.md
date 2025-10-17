# Building a Vercel-Hosted Web Dashboard for Tesseract OCR

This tutorial takes a pedagogical, component-driven approach to configuring a pure web dashboard on Vercel that delegates heavyweight OCR processing to an external Tesseract service. Each section introduces the architectural concept first, then shows how to realise it in code, and finally outlines quantitative measures that help you evaluate sustainability over time.

## 1. Architectural overview

We model the dashboard as a composition of modular components grouped into three collaborating layers:

1. **Presentation layer (Vercel frontend)** – Next.js or Nuxt.js renders deterministic UI components, manages authentication, and collects telemetry.
2. **Orchestration layer (serverless and edge helpers)** – Vercel functions validate requests, enqueue jobs, and expose status polling APIs.
3. **OCR execution layer (external service)** – A dedicated Tesseract-based backend such as [`hertzg/tesseract-server`](https://github.com/hertzg/tesseract-server) or OpenOCR, deployed on container platforms (Fly.io, Railway, Kubernetes, etc.).

This separation keeps latency-sensitive UI work inside Vercel while isolating CPU-intensive OCR in an environment with predictable resource limits.

## 2. Component-driven UI model

The presentation layer is articulated as deterministic components so that behaviour can be reasoned about independently:

- **UploadPanel** – Handles file selection, drag-and-drop, and validation. Model the state machine (`idle → validating → queued`) explicitly to capture memory usage and client-side compute requirements.
- **JobTimeline** – Polls orchestration APIs and renders progress updates. Memoise selectors to minimise re-renders and record fan-in (number of upstream data sources) as a maintainability metric.
- **ResultViewer** – Presents recognised text, hOCR, or PDF previews. Keep pagination, diffing, and export features behind clearly named props to avoid competing paradigms inside a single module.

### Measuring architectural properties

| Property | Measurement technique | Interpretation |
| --- | --- | --- |
| Maintainability | Count shared-state dependencies per component (Redux stores, React Query caches). | Lower counts imply easier refactors and clearer ownership boundaries. |
| Scalability | Track the maximum concurrent renders per component during load tests. | Components that spike concurrently may need code-splitting or streaming. |
| Sustainability | Record the ratio of deterministic components (pure functions + memoisation) to side-effect-heavy components. | A higher ratio indicates resilience against technical debt accumulation. |

## 3. Repository setup

1. **Initialize the project**
   ```bash
   npx create-next-app@latest ocr-dashboard
   cd ocr-dashboard
   npm install @tanstack/react-query axios
   ```

2. **Configure environment variables** (create `.env.local`):
   ```bash
   NEXT_PUBLIC_OCR_API_URL="https://ocr-backend.example.com"
   ```

3. **Implement typed API client** (`lib/ocrClient.ts`):
   ```ts
   import axios from "axios";

   const client = axios.create({
     baseURL: process.env.NEXT_PUBLIC_OCR_API_URL,
   });

   export const submitJob = (file: File) => {
     const formData = new FormData();
     formData.append("file", file);
     return client.post("/jobs", formData);
   };

   export const getJobStatus = (jobId: string) => client.get(`/jobs/${jobId}`);
   export const getJobResult = (jobId: string) => client.get(`/jobs/${jobId}/result`);
   ```

   Track exported functions against backend capabilities. A one-to-one mapping keeps the maintainability metric in the previous section low and prevents accidental coupling.

4. **Compose dashboard page** (`app/page.tsx` or `pages/index.tsx`):
   ```tsx
   "use client";

   import { useState } from "react";
   import { useMutation, useQuery } from "@tanstack/react-query";
   import { submitJob, getJobStatus, getJobResult } from "@/lib/ocrClient";

   export default function Dashboard() {
     const [jobId, setJobId] = useState<string | null>(null);

     const submitMutation = useMutation({
       mutationFn: submitJob,
       onSuccess: (res) => setJobId(res.data.jobId),
     });

     const statusQuery = useQuery({
       queryKey: ["ocrStatus", jobId],
       queryFn: () => getJobStatus(jobId!),
       enabled: Boolean(jobId),
       refetchInterval: (q) => (q.state.data?.data.status === "completed" ? false : 2000),
     });

     const resultQuery = useQuery({
       queryKey: ["ocrResult", jobId],
       queryFn: () => getJobResult(jobId!),
       enabled: statusQuery.data?.data.status === "completed",
     });

     return (
       <main className="mx-auto max-w-3xl p-6 space-y-8">
         <section>
           <h1 className="text-2xl font-semibold">Tesseract OCR Dashboard</h1>
           <p className="text-sm text-gray-500">Upload an image or PDF to process via the backend API.</p>
         </section>

         <UploadPanel
           onSubmit={(file) => submitMutation.mutate(file)}
           isLoading={submitMutation.isPending}
         />

         <JobTimeline status={statusQuery.data?.data} />

         {resultQuery.data?.data && <ResultViewer result={resultQuery.data.data} />}
       </main>
     );
   }
   ```

   Inline components (`UploadPanel`, `JobTimeline`, `ResultViewer`) should be modularised into separate files as soon as they gain additional props. Note the average component size in lines of code so you can quantify growth over time.

## 4. Orchestration layer on Vercel

- **API Route (`app/api/jobs/route.ts`)** – Accept uploads, validate MIME types, and forward them to the external OCR service. Stream large files to object storage (S3, R2) and send references to the backend to preserve memory budgets.
- **Status Route (`app/api/jobs/[id]/route.ts`)** – Proxy status requests to the OCR service. Cache short-lived responses with Vercel’s `revalidateTag` to flatten peak load.
- **Security** – Use Vercel environment variables for credentials and apply rate limiting middleware (e.g., Upstash Redis) against abuse.

Quantify complexity by counting the number of downstream integrations per route and logging median response latency. Document these values in your repo so future contributors can project the impact of feature changes.

## 5. External OCR backend

1. **Deploy Tesseract service**
   ```bash
   docker run -d \
     -p 8080:8080 \
     -e TESSDATA_PREFIX=/usr/share/tesseract-ocr/4.00/tessdata \
     ghcr.io/hertzg/tesseract-server:latest
   ```

2. **Expose secure endpoint** – Place the container behind HTTPS (Caddy, Nginx, or Cloudflare Tunnel).
3. **Configure scaling** – Use horizontal scaling (multiple replicas) if your workload includes concurrent OCR jobs. Monitor CPU usage and job duration histograms to predict when to provision additional replicas.

## 6. Deployment on Vercel

1. **Push to Git repository** and connect it to Vercel.
2. **Set build configuration**:
   - Framework Preset: `Next.js`
   - Build Command: `npm run build`
   - Output Directory: `.next`
3. **Environment variables** – Add `NEXT_PUBLIC_OCR_API_URL` and any secrets (auth tokens) under **Settings → Environment Variables** in the Vercel dashboard.
4. **Storage & edge functions** – Enable Vercel KV or Blob storage if you need temporary artifacts. Evaluate cost vs. complexity.

Measure sustainability by reviewing deploy times and bundle sizes; Vercel analytics expose these metrics for continuous monitoring.

## 7. Run configurations on Vercel

Document run configurations in version control (for example, `/docs/run-configurations.md`) so operational settings evolve with the code.

- **Runtime targets** – Prefer the Edge Runtime for lightweight proxy routes and `Node.js 18+` for file uploads. Record average cold-start latency so you can weigh migrations against end-user experience.
- **Regions** – Pin latency-sensitive components (upload, status polling) to the region closest to primary users and track a “distance penalty” metric (additional latency in milliseconds) for secondary regions.
- **Concurrency safeguards** – Configure invocation limits and queue settings per function, then chart concurrent execution counts to spot saturation before it harms throughput.
- **Build & preview rules** – Align preview deployments with feature branches. Store merge gating rules (required checks, review counts) so deterministic release criteria remain visible.

These artefacts close the loop between component intent and deployed behaviour, ensuring architectural measurements stay reproducible.

## 8. Adaptations for alternative requirements

Use the baseline architecture as a foundation and extend it deliberately when constraints evolve:

- **Offline-first workflows** – Add an IndexedDB-backed cache for `ResultViewer`. Track cache hit ratios alongside bundle size increases to estimate the performance trade-off.
- **Multitenancy** – Introduce a `TenantContext` provider that scopes API credentials and rate limits. Record the number of tenant-specific overrides per component to gauge complexity growth.
- **Advanced analytics** – Append a `QualityInsights` component that pairs OCR confidence with domain heuristics. Keep it as a sibling module to the dashboard to avoid paradigm clashes and update the technical-debt register with new dependencies.
- **Regulated deployments** – Swap Vercel-managed storage with a BYO object store (S3, Azure Blob) when compliance dictates retention controls. Document the data residency matrix so auditors can verify flows quickly.

After each adaptation, revisit the maintainability and sustainability metrics introduced earlier to confirm the component model still behaves predictably.

## 9. Observability and sustainability metrics

- **Client metrics** – Use Vercel Web Vitals, segmented per component (for example, `UploadPanel` interaction time). Plot these alongside code-splitting decisions to reason about scalability.
- **Backend metrics** – Track job duration, queue depth, and error rates from the OCR service; correlate spikes with deploy timestamps to isolate regressions.
- **Technical debt scoring** – Periodically review component boundaries. Count competing paradigms (for example, mixing server and client components for the same UI region) and compute a “paradigm overlap ratio” (conflicting paradigms ÷ total paradigms) to estimate complexity.

## 10. Testing strategy (run tests ×3)

Validate behaviour with a repeatable, multi-pass regimen to surface flaky integrations:

1. `npm run lint`
2. `npm run test`
3. `npm run test`

Log duration and exit status for each run. Store the data in your repository (for example, `reports/test-run-history.json`) so you can chart variance over time and prove deterministic behaviour before deploying to production. When tests hit live OCR services, target sandbox endpoints to preserve production quotas.

## 11. Practical limitations and automation opportunities

- Vercel serverless functions have constrained execution time and memory, so shift CPU-bound OCR to the external service.
- Large PDFs benefit from chunked uploads or asynchronous callbacks via object storage to maintain responsiveness.
- Automated code generation (for example, Nx or Plop.js templates) can scaffold consistent component shells. Integrate generation scripts with lint rules so the produced code adheres to your maintainability metrics.

## 12. Future development

- **Sustainability forecasting** – Use the collected metrics to model the probability that the architecture remains maintainable under projected feature growth.
- **Complexity modelling** – Refine the paradigm overlap ratio to account for inter-component dependencies and state-sharing heuristics.
- **Tooling integration** – Explore automated dashboards that pull observability data and test history into a single sustainability report for stakeholders.

By iterating on these practices, you maintain a Vercel-hosted dashboard that is both technically sustainable and aligned with long-term OCR goals.
