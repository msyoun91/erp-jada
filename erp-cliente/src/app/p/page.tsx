import type { Metadata } from "next";
import { Presupuesto } from "./Presupuesto";

export const metadata: Metadata = { title: "Presupuesto — JADA", robots: { index: false, follow: false } };

export default function Page() {
  return <Presupuesto />;
}
