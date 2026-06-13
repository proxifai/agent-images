import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/**
 * cn — Tailwind-aware class merger. Lifted verbatim from shadcn/ui so
 * the components shipped under src/components/ui/ work without
 * modification. Use it in your own components too:
 *
 *   <div className={cn("p-4", isActive && "bg-primary text-primary-foreground")}>
 */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
