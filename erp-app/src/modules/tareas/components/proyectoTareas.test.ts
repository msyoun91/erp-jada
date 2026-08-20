// Sin runner de tests en el repo: `node --test src/modules/tareas/components/proyectoTareas.test.ts`
// desde erp-app (Node 24 despoja los tipos solo). Mismo criterio que relacion.test.ts.
import { strict as assert } from "node:assert";
import { test } from "node:test";
import { puedeTrabajarEnProyecto } from "./proyectoTareas.ts";

const YO = "u1";
const OTRO = "u2";

test("sin tareas_asignar: hace falta ser miembro", () => {
  assert.equal(puedeTrabajarEnProyecto([YO], YO, false), true);
  assert.equal(puedeTrabajarEnProyecto([OTRO], YO, false), false);
  assert.equal(puedeTrabajarEnProyecto([], YO, false), false);
});

test("con tareas_asignar: alcanza con que haya un miembro visible", () => {
  assert.equal(puedeTrabajarEnProyecto([OTRO], YO, true), true);
  assert.equal(puedeTrabajarEnProyecto([], YO, true), false);
});

test("sin sesión nunca se puede trabajar sin la función", () => {
  assert.equal(puedeTrabajarEnProyecto([YO], null, false), false);
});
