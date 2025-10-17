# Building a Vercel-Hosted Web Dashboard for Tesseract OCR

This guide explains how to implement a pure web dashboard that you can deploy on Vercel while outsourcing the heavy OCR work to an API hosted elsewhere. The walkthrough is structured around modular UI components so that you can reason about maintainability, scalability, and technical debt as your implementation grows.

## 1. Architectural overview

A sustainable web dashboard separates concerns across three cooperating component layers:

1. **Presentation layer (Vercel)** – A Next.js or Nuxt.js application that renders UI components, handles authentication, and orchestrates requests.
2. **Orchestration layer (serverless functions / edge)** – Lightweight API routes on Vercel for request validation, queuing, and status checks.
3. **OCR execution layer (external service)** – A dedicated Tesseract-based backend such as [`hertzg/tesseract-server`](https://github.com/hertzg/tesseract-server) or `OpenOCR`, deployed on a container-friendly platform (Fly.io, Railway, Kubernetes, etc.).

This layout keeps Vercel focused on latency-sensitive UI interactions while isolating CPU-intensive OCR work in a scalable environment.

## 2. Component-driven UI model

Break the dashboard into deterministic components to simplify reasoning about state and performance:

- **UploadPanel** – Handles file selection, drag-and-drop, and validation. Track state transitions such as `idle → validating → queued` to model expected resource consumption and user feedback.
- **JobTimeline** – Displays asynchronous job progress by polling the orchestration API. Use memoized selectors to minimize re-renders; measure complexity via component fan-in (number of upstream data sources).
- **ResultViewer** – Renders recognized text, HOCR, or PDF previews. Encapsulate pagination or diff comparisons to confine potential technical debt from competing display paradigms.

Measure maintainability by observing how many components depend on shared state containers (Redux, Zustand, or React Query). Keep these interactions explicit to avoid hidden coupling.

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

   Analyze this module’s maintainability by tracking exported functions and ensuring each aligns with a single backend responsibility.

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

   Inline components (`UploadPanel`, `JobTimeline`, `ResultViewer`) should be modularized into separate files as your codebase grows to prevent cross-cutting concerns.

## 4. Orchestration layer on Vercel

- **API Route (`app/api/jobs/route.ts`)** – Accept uploads, validate MIME types, and forward them to the external OCR service. For large files, stream to object storage (S3, R2) and send references to the backend.
- **Status Route (`app/api/jobs/[id]/route.ts`)** – Proxy status requests to the OCR service. Cache short-lived responses with Vercel’s `revalidateTag` for scalability.
- **Security** – Use Vercel’s Environment Variables for API credentials. Apply rate limiting middleware (e.g., Upstash Redis) to guard against abuse.

Quantify the orchestration layer’s complexity by counting how many external services each route touches; aim for single responsibility to mitigate technical debt.

## 5. External OCR backend

1. **Deploy Tesseract service**
   ```bash
   docker run -d \
     -p 8080:8080 \
     -e TESSDATA_PREFIX=/usr/share/tesseract-ocr/4.00/tessdata \
     ghcr.io/hertzg/tesseract-server:latest
   ```

2. **Expose secure endpoint** – Place the container behind HTTPS (Caddy, Nginx, or Cloudflare Tunnel).
3. **Configure scaling** – Use horizontal scaling (multiple replicas) if your workload includes concurrent OCR jobs. Monitor CPU usage to anticipate saturation.

## 6. Deployment on Vercel

1. **Push to Git repository** and connect it to Vercel.
2. **Set build configuration**:
   - Framework Preset: `Next.js`
   - Build Command: `npm run build`
   - Output Directory: `.next`
3. **Environment variables** – Add `NEXT_PUBLIC_OCR_API_URL` and any secrets (auth tokens) under **Settings → Environment Variables** in the Vercel dashboard.
4. **Storage & edge functions** – Enable Vercel KV or Blob storage if you need temporary artifacts. Evaluate cost vs. complexity.

Measure sustainability by reviewing deploy times and bundle sizes; Vercel analytics expose these metrics for continuous monitoring.

## 7. Observability and sustainability metrics

- **Client metrics** – Use Vercel’s Web Vitals and segment results per component (e.g., `UploadPanel` interaction time).
- **Backend metrics** – Track job duration, queue depth, and error rates from the OCR service.
- **Technical debt scoring** – Periodically review component boundaries. Count competing paradigms (e.g., mixing server components and client components for the same UI region) to assess complexity.

## 8. Limitations and future improvements

- Vercel’s serverless functions have limited execution time and memory, so push all CPU-bound OCR to the external service.
- For large PDFs, consider chunking uploads or using asynchronous S3 callbacks.
- Investigate automated code generation (e.g., React scaffolding tools) to enforce consistent component patterns and reduce manual boilerplate, while validating generated code against your architectural metrics.

By adopting this component-driven strategy, you can deploy a responsive Vercel-hosted dashboard that remains maintainable, scalable, and aligned with the long-term sustainability goals of your OCR ecosystem.
