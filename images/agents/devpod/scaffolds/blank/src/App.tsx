import { useState } from "react";
import { Sparkles, Zap } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export default function App() {
  const [count, setCount] = useState(0);
  return (
    <main className="flex min-h-screen items-center justify-center bg-background p-8 text-foreground">
      <Card className="w-full max-w-lg">
        <CardHeader>
          <div className="flex items-center justify-between">
            <Badge variant="secondary" className="gap-1">
              <span className="size-1.5 rounded-full bg-emerald-400" />
              Live preview ready
            </Badge>
            <Badge variant="outline" className="gap-1 text-xs">
              <Sparkles className="size-3" />
              ProxiBuild
            </Badge>
          </div>
          <CardTitle className="pt-2 text-3xl tracking-tight">
            Your blank canvas
          </CardTitle>
          <CardDescription>
            Tell the assistant what to build and watch it appear here in real time.
            Every file edit triggers vite&apos;s HMR and the iframe updates instantly.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="rounded-md border bg-card/60 p-4 text-center">
            <div className="text-5xl font-semibold tabular-nums">{count}</div>
            <div className="mt-1 text-xs text-muted-foreground">
              clicks · proof the React + Tailwind + shadcn stack is wired
            </div>
          </div>
          <div className="flex gap-2">
            <Button onClick={() => setCount((c) => c + 1)} className="flex-1">
              <Zap className="size-4" />
              Add one
            </Button>
            <Button variant="outline" onClick={() => setCount(0)}>
              Reset
            </Button>
          </div>
          <p className="text-xs text-muted-foreground">
            Edit <code className="rounded bg-secondary px-1 py-0.5 font-mono">src/App.tsx</code> directly or ask the assistant to change anything.
          </p>
        </CardContent>
      </Card>
    </main>
  );
}
