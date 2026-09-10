// Sin runner de tests en el repo: `node --test src/modules/tareas/origen.test.ts`
// desde erp-app (Node 24 despoja los tipos solo). Mismo criterio que relacion.test.ts.
import { strict as assert } from "node:assert";
import { test } from "node:test";
import { origenHref } from "./origen.ts";

test("solo rutas internas llegan al href", () => {
  assert.equal(origenHref("/compras/oc/1"), "/compras/oc/1");
  assert.equal(origenHref(null), null);
  assert.equal(origenHref("javascript:alert(1)"), null);
  assert.equal(origenHref("https://evil.com"), null);
  assert.equal(origenHref("//evil.com"), null);
});
