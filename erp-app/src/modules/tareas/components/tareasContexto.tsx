"use client";

import { createContext, useContext } from "react";
import type { TareaProyecto, Usuario } from "../types";

// Los seis datos que toda la UI del módulo necesita para dibujar una tarea:
// quién puede recibirla, dónde vive, quién la mira y qué le está permitido.
// Viajaban como props idénticas por 13 archivos — `Bloqueadas` recibía nueve
// para usar tres. No son estado: los arma la page en el server y no cambian
// hasta el próximo revalidate.
export type TareasContexto = {
  usuarios: Usuario[];
  proyectos: TareaProyecto[];
  miembrosPorProyecto: Record<string, string[]>;
  usuarioActualId: string | null;
  gestionarAjenas: boolean;
  puedeAsignar: boolean;
};

const Contexto = createContext<TareasContexto | null>(null);

export function TareasContextoProvider({
  valor,
  children,
}: {
  valor: TareasContexto;
  children: React.ReactNode;
}) {
  return <Contexto.Provider value={valor}>{children}</Contexto.Provider>;
}

export function useTareasContexto(): TareasContexto {
  const valor = useContext(Contexto);
  if (!valor) throw new Error("useTareasContexto fuera de TareasContextoProvider");
  return valor;
}
