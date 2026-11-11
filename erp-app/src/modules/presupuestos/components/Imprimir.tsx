"use client";

import { Printer } from "lucide-react";

// Imprime o guarda como PDF desde el navegador, sin librería (decisiones/presupuestos.md → *El cliente y el portal*).
export function Imprimir() {
  return (
    <button type="button" className="btn btn-primary btn-sm" onClick={() => window.print()}>
      <Printer size={14} />
      Imprimir
    </button>
  );
}
