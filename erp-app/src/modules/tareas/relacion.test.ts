// Sin runner de tests en el repo: `node --test src/modules/tareas/relacion.test.ts`
// desde erp-app (Node 24 despoja los tipos solo). No agrega dependencias.
import { strict as assert } from "node:assert";
import { test } from "node:test";
import { relacionHilo, relacionTarea } from "./relacion.ts";
import type { TareaConAsignados, TareaHilo } from "./types.ts";

const YO = "u1";
const OTRO = "u2";

function tarea(
  over: Partial<TareaConAsignados> & { asignados?: { usuario_id: string; activo: boolean }[] } = {},
): TareaConAsignados {
  const { asignados = [], ...rest } = over;
  return {
    id: "t1",
    responsable_id: OTRO,
    creado_por: OTRO,
    hilo_id: null,
    tareas_asignados: asignados.map((a) => ({ ...a, usuarios: null })),
    ...rest,
  } as unknown as TareaConAsignados;
}

test("responsable gana sobre asignado", () => {
  assert.equal(relacionTarea(tarea({ responsable_id: YO }), YO), "responsable");
});

test("asignado activo cuenta, inactivo no", () => {
  assert.equal(relacionTarea(tarea({ asignados: [{ usuario_id: YO, activo: true }] }), YO), "asignado");
  assert.equal(relacionTarea(tarea({ asignados: [{ usuario_id: YO, activo: false }] }), YO), null);
});

test("creado_por no da relación", () => {
  assert.equal(relacionTarea(tarea({ creado_por: YO }), YO), null);
});

test("dueño del hilo sin pasos asignados es responsable", () => {
  const hilo = { id: "h1", responsable_id: YO } as TareaHilo;
  assert.equal(relacionHilo(hilo, [tarea()], YO), "responsable");
});

test("un solo paso propio involucra en el hilo ajeno", () => {
  const hilo = { id: "h1", responsable_id: OTRO } as TareaHilo;
  const pasos = [tarea({ id: "a" }), tarea({ id: "b", asignados: [{ usuario_id: YO, activo: true }] })];
  assert.equal(relacionHilo(hilo, pasos, YO), "asignado");
  assert.equal(relacionHilo(hilo, [tarea()], YO), null);
});
