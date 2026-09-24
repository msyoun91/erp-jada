// Sin runner de tests en el repo: `node --test src/modules/tareas/derivados.test.ts`
// desde erp-app (Node despoja los tipos solo).
import { strict as assert } from "node:assert";
import { test } from "node:test";
import { compararMision, esHuerfano, estaBloqueado, estaEnEspera, estaVencido, ordenarPasos } from "./derivados.ts";
import type { EstadoTarea } from "./types.ts";

type P = { id: string; paso_anterior_id: string | null; estado: EstadoTarea; created_at: string };

function paso(id: string, previo: string | null, estado: EstadoTarea, created_at = id): P {
  return { id, paso_anterior_id: previo, estado, created_at };
}

function mapa(pasos: P[]) {
  return new Map(pasos.map((p) => [p.id, p]));
}

test("bloqueado: previo pendiente bloquea, completado habilita", () => {
  const a = paso("a", null, "pendiente");
  const b = paso("b", "a", "pendiente");
  assert.equal(estaBloqueado(b, mapa([a, b])), true);
  assert.equal(estaBloqueado(b, mapa([{ ...a, estado: "completada" }, b])), false);
  assert.equal(estaBloqueado(a, mapa([a, b])), false);
});

test("bloqueado: el cancelado es transparente", () => {
  const a = paso("a", null, "pendiente");
  const b = paso("b", "a", "cancelada");
  const c = paso("c", "b", "pendiente");
  assert.equal(estaBloqueado(c, mapa([a, b, c])), true);
  assert.equal(estaBloqueado(c, mapa([{ ...a, estado: "completada" }, b, c])), false);
  assert.equal(estaBloqueado(c, mapa([{ ...a, estado: "cancelada" }, b, c])), false);
});

test("bloqueado: un cerrado nunca está bloqueado", () => {
  const a = paso("a", null, "pendiente");
  const b = paso("b", "a", "completada");
  assert.equal(estaBloqueado(b, mapa([a, b])), false);
});

test("ordenar: cadenas contiguas, raíces por alta, huérfano de previo arranca cadena", () => {
  const pasos = [
    paso("c2", "c1", "pendiente", "5"),
    paso("x", null, "pendiente", "2"),
    paso("c1", null, "pendiente", "1"),
    paso("c3", "c2", "pendiente", "6"),
    paso("h", "desactivado", "pendiente", "3"),
  ];
  assert.deepEqual(
    ordenarPasos(pasos).map((p) => p.id),
    ["c1", "c2", "c3", "x", "h"]
  );
});

test("espera y vencido", () => {
  assert.equal(estaEnEspera({ estado: "pendiente", espera_hasta: "2026-10-01" }, "2026-09-24"), true);
  assert.equal(estaEnEspera({ estado: "pendiente", espera_hasta: "2026-09-24" }, "2026-09-24"), false);
  assert.equal(estaVencido({ estado: "pendiente", vence: "2026-09-23" }, "2026-09-24"), true);
  assert.equal(estaVencido({ estado: "completada", vence: "2026-09-23" }, "2026-09-24"), false);
  assert.equal(estaVencido({ estado: "pendiente", vence: "2026-09-24" }, "2026-09-24"), false);
});

test("misión: prioridad, después vence (sin fecha al final), después alta", () => {
  const p = (id: string, prioridad: "alta" | "media" | "baja", vence: string | null) => ({ id, prioridad, vence, created_at: id });
  const orden = [p("d", "media", null), p("c", "media", "2026-10-02"), p("a", "baja", "2026-01-01"), p("b", "alta", null), p("e", "media", "2026-10-01"), p("f", "media", null)]
    .sort(compararMision)
    .map((x) => x.id);
  assert.deepEqual(orden, ["b", "e", "c", "d", "f", "a"]);
});

const asignables = [
  { usuario_id: "ana", equipo_id: null, pedido: false, puede_recibir: true },
  { usuario_id: "beto", equipo_id: null, pedido: false, puede_recibir: false },
  { usuario_id: "caro", equipo_id: null, pedido: true, puede_recibir: true },
];

test("huérfano: responsable o asignado abierto que no recibe; inactivo no figura", () => {
  const hilo = (responsable_id: string, asignado: string, estado: EstadoTarea = "pendiente") => ({
    activo: true,
    estado: "abierto",
    responsable_id,
    tareas: [{ activo: true, estado, asignado_id: asignado, asignado_equipo_id: null }],
  });
  assert.equal(esHuerfano(hilo("ana", "ana"), asignables), false);
  assert.equal(esHuerfano(hilo("beto", "ana"), asignables), true);
  assert.equal(esHuerfano(hilo("ana", "dani"), asignables), true);
  assert.equal(esHuerfano(hilo("ana", "dani", "completada"), asignables), false);
  assert.equal(esHuerfano({ ...hilo("beto", "ana"), estado: "cerrado" }, asignables), false);
});
