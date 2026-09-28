import { test, expect, type Page } from "@playwright/test";
import { como, crearIgual, panel } from "./comun";

// Tramo 3: compartir empresa. Caputo es de "Equipo Zqx pruebas" (Norte, el de
// Pedro); el admin la comparte con "Equipo Zqx sur", donde está Juan (tester),
// que la ve en su lista como compartida y no la comparte él. Al dejar de
// compartir, Juan deja de verla. Juan sale de Sur al final: `obras.spec.ts` lo
// suma a Norte.
const marca = `Zqx${Date.now() % 100000}`;
const caputo = `Constructora Caputo ${marca}`;
const norte = "Equipo Zqx pruebas";
const sur = "Equipo Zqx sur";

function seccion(page: Page, equipo: string) {
  return page.locator("section").filter({ has: page.getByRole("heading", { name: equipo }) });
}

async function asegurarEquipo(page: Page, equipo: string) {
  await page.goto("/usuarios/equipos");
  await expect(page.getByRole("button", { name: "Nuevo equipo" })).toBeVisible();
  if ((await seccion(page, equipo).count()) > 0) return;
  await page.getByRole("button", { name: "Nuevo equipo" }).click();
  const alta = panel(page);
  await alta.getByLabel("Nombre").fill(equipo);
  await alta.getByRole("button", { name: "Crear equipo" }).click();
  await expect(seccion(page, equipo)).toBeVisible();
}

test("Norte comparte Caputo con Sur y deja de compartirla", async ({ browser }) => {
  test.setTimeout(120_000);
  const { ctx: ctxAdmin, page: admin } = await como(browser, "admin");
  await asegurarEquipo(admin, norte);
  await asegurarEquipo(admin, sur);
  const deSur = seccion(admin, sur);
  if ((await deSur.getByText("Tester", { exact: true }).count()) === 0) {
    await deSur.locator("header").getByRole("button", { name: "Más acciones" }).click();
    await admin.getByRole("button", { name: "Agregar miembro" }).click();
    const alta = panel(admin);
    await alta.getByLabel("Usuario").selectOption({ label: "Tester" });
    await alta.getByRole("button", { name: "Agregar" }).click();
    await expect(deSur.getByText("Tester", { exact: true })).toBeVisible();
  }

  try {
    // El admin carga Caputo y se la pasa a Norte.
    await admin.goto("/contactos/empresas");
    await admin.getByRole("button", { name: "Nueva empresa" }).click();
    const alta = panel(admin);
    await alta.getByLabel("Nombre").fill(caputo);
    const url = await crearIgual(admin, alta, "Crear empresa", /\/contactos\/empresas\/[0-9a-f-]{36}$/);
    await admin.getByRole("button", { name: "Más acciones" }).click();
    await admin.getByRole("button", { name: "Asignar equipo" }).click();
    const equipo = panel(admin);
    await equipo.getByLabel("Equipo").selectOption({ label: norte });
    await equipo.getByRole("button", { name: "Guardar" }).click();
    await expect(admin.getByTitle("Equipo")).toHaveText(norte);

    const { ctx: ctxJuan, page: juan } = await como(browser, "tester");
    await juan.goto("/contactos/empresas");
    await expect(juan.getByRole("button", { name: "Nueva empresa" })).toBeVisible();
    await expect(juan.getByRole("link", { name: caputo })).toHaveCount(0);

    // Compartir: Sur aparece en la ficha y ya no se ofrece.
    await admin.getByRole("button", { name: "Más acciones" }).click();
    await admin.getByRole("button", { name: "Compartir con otro equipo" }).click();
    const compartir = panel(admin);
    await expect(compartir.getByRole("option", { name: norte })).toHaveCount(0);
    await compartir.getByLabel("Equipo").selectOption({ label: sur });
    await compartir.getByRole("button", { name: "Compartir" }).click();
    await expect(compartir).toBeHidden();
    await expect(admin.getByText("Compartida con")).toBeVisible();
    await expect(admin.getByRole("button", { name: `Dejar de compartir con ${sur}` })).toBeVisible();

    // Juan la ve en su lista, marcada, y en la ficha no la comparte.
    await juan.reload();
    const fila = juan.getByRole("link", { name: caputo });
    await expect(fila.getByText(`Compartida por ${norte}`)).toBeVisible();
    await fila.click();
    await expect(juan.getByRole("heading", { name: caputo })).toBeVisible();
    await expect(juan.getByText("Compartida con")).toBeVisible();
    await expect(juan.getByRole("button", { name: `Dejar de compartir con ${sur}` })).toHaveCount(0);
    await juan.getByRole("button", { name: "Más acciones" }).click();
    await expect(juan.getByRole("button", { name: "Editar" })).toBeVisible();
    await expect(juan.getByRole("button", { name: "Compartir con otro equipo" })).toHaveCount(0);
    await juan.keyboard.press("Escape");

    // Dejar de compartir: Juan deja de verla.
    await admin.getByRole("button", { name: `Dejar de compartir con ${sur}` }).click();
    await panel(admin).getByRole("button", { name: "Dejar de compartir" }).click();
    await expect(admin.getByText("Compartida con")).toHaveCount(0);

    await juan.goto("/contactos/empresas");
    await expect(juan.getByRole("button", { name: "Nueva empresa" })).toBeVisible();
    await expect(juan.getByRole("link", { name: caputo })).toHaveCount(0);
    await juan.goto(url);
    await expect(juan.getByRole("heading", { name: caputo })).toHaveCount(0);
    await ctxJuan.close();
  } finally {
    await admin.goto("/usuarios/equipos");
    await expect(deSur.getByText("Tester", { exact: true })).toBeVisible();
    const fila = deSur.locator("div.row").filter({ has: admin.getByText("Tester", { exact: true }) });
    await fila.getByRole("button", { name: "Más acciones" }).click();
    await admin.getByRole("button", { name: "Sacar del equipo" }).click();
    const sacar = panel(admin);
    await sacar.getByRole("checkbox", { name: /Su agenda pasa al jefe/ }).uncheck();
    await sacar.getByRole("button", { name: "Sacar" }).click();
    await expect(deSur.getByText("Tester", { exact: true })).toHaveCount(0);
    await ctxAdmin.close();
  }
});
