import { test, expect } from "@playwright/test";
import { aprobarPendientes, como, crearIgual, panel } from "./comun";

// Tramo 5 de Tareas: Juan (tester) arma una plantilla sobre la obra con un paso
// que se completa solo al vincular un arquitecto, y la usa sobre una obra suya
// sin arquitecto. Todo lleva el marcador.
const marca = `Zqx${Date.now() % 100000}`;
const plantilla = `Seguimiento de obra ${marca}`;
const obra = `Obra con plantilla ${marca}`;

test.describe.configure({ mode: "serial" });

test("Juan arma una plantilla sobre la obra que corre sola", async ({ browser }) => {
  const { ctx, page } = await como(browser, "tester");
  await page.goto("/tareas/plantillas");
  await page.getByRole("button", { name: "Nueva plantilla" }).click();
  const form = panel(page);
  await form.getByLabel("Nombre").fill(plantilla);
  await form.getByLabel("Sobre").selectOption({ label: "Obra" });
  await form.getByLabel("Corre sola").selectOption({ label: "Al pasar a Contratada" });
  await form.getByRole("checkbox", { name: "Activa" }).check();

  await form.getByLabel("Título", { exact: true }).fill("Vincular arquitecto");
  await form.getByRole("button", { name: "+ Obra" }).click();
  await expect(form.getByLabel("Descripción").nth(1)).toHaveValue("{@registro}");
  await form.getByLabel("Se completa").selectOption({ label: "Al vincular arquitecto" });
  await form.getByRole("group", { name: "Insertar en la descripción" }).first().getByRole("button", { name: "+ Link de acción" }).click();
  await expect(form.getByLabel("Descripción").nth(1)).toHaveValue("{@registro} {@accion|Vincular arquitecto}");

  await form.getByRole("button", { name: "Sumar paso" }).click();
  await form.getByLabel("Título", { exact: true }).nth(1).fill("Coordinar con el arquitecto");
  await form.getByRole("group", { name: "Insertar en la descripción" }).nth(1).getByRole("button", { name: "+ Arquitecto" }).click();
  await form.getByLabel("Entra").nth(1).selectOption({ label: "Si hay arquitecto" });

  await form.getByRole("button", { name: "Crear plantilla" }).click();
  await expect(form).toBeHidden();

  const card = page.locator("div.card").filter({ hasText: plantilla });
  await expect(card).toContainText("Sobre: Obra");
  await expect(card).toContainText("Al pasar a Contratada");
  await card.getByText("Ver pasos").click();
  await expect(card).toContainText("Se completa sola al vincular arquitecto");
  await expect(card).toContainText("Si hay arquitecto");

  await card.getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Editar" }).click();
  const editar = panel(page);
  await expect(editar.getByLabel("Sobre")).toHaveValue("obra");
  await expect(editar.getByLabel("Corre sola")).toHaveValue("estado:contratada");
  await expect(editar.getByRole("checkbox", { name: "Activa" })).toBeChecked();
  await expect(editar.getByLabel("Se completa").first()).toHaveValue("relacion_alta:arquitecto");
  await expect(editar.getByLabel("Entra").nth(1)).toHaveValue("arquitecto");
  await editar.getByRole("button", { name: "Cancelar" }).click();
  await ctx.close();
});

test("Juan la usa sobre su obra y el paso sin arquitecto no entra", async ({ browser }) => {
  test.setTimeout(120_000);
  const { ctx, page } = await como(browser, "tester");
  await page.goto("/obras");
  await page.getByRole("button", { name: "Nueva obra" }).click();
  const alta = panel(page);
  await alta.getByLabel("Nombre", { exact: true }).fill(obra);
  await alta.getByLabel("Dirección").fill(`Calle ${marca} 100`);
  await alta.getByLabel("Tipo de obra").selectOption({ label: "Edificio residencial" });
  await alta.getByLabel("Origen").selectOption("cartel");
  await crearIgual(page, alta, "Crear obra", /\/obras\/[0-9a-f-]{36}$/);
  await aprobarPendientes(browser, marca);

  await page.goto("/tareas/plantillas");
  const card = page.locator("div.card").filter({ hasText: plantilla });
  await card.getByRole("button", { name: "Usar" }).click();
  const usar = panel(page);
  await expect(usar.getByRole("button", { name: "Crear hilo" })).toBeDisabled();
  await usar.getByPlaceholder("Buscar una obra").fill(obra);
  await usar.getByRole("button", { name: obra }).click();
  await expect(usar).toContainText("Se completa sola al vincular arquitecto");
  await expect(usar).toContainText("No entra: la obra no tiene arquitecto");
  await usar.getByRole("button", { name: "Crear hilo" }).click();

  await expect(page).toHaveURL(/\/tareas\/[0-9a-f-]{36}$/);
  // La ficha de la obra no va al lado del hilo: se ve al abrir el paso.
  await expect(page.getByRole("heading", { name: obra })).toHaveCount(0);
  await expect(page.getByText("Vincular arquitecto").first()).toBeVisible();
  await expect(page.getByText("Coordinar con el arquitecto")).toHaveCount(0);

  await page.getByText("Vincular arquitecto").first().click();
  const paso = panel(page);
  await expect(paso).toContainText("Se completa sola");
  await expect(paso).toContainText("Al vincular arquitecto");
  // La obra del hilo es la primera pestaña, con su ficha entera; `{@registro}`
  // en el texto no suma otra y su ↗ la activa sin salir del paso.
  await expect(paso.getByRole("tab", { name: obra })).toHaveAttribute("aria-selected", "true");
  await expect(paso.getByRole("tab")).toHaveCount(1);
  await expect(paso.getByRole("tabpanel", { name: obra }).getByRole("heading", { name: obra })).toBeVisible();
  await expect(paso.getByRole("tabpanel", { name: obra }).getByText("Hilos", { exact: true })).toHaveCount(0);
  await paso.getByRole("button", { name: `${obra} ↗` }).click();
  await expect(page).toHaveURL(/\/tareas\/[0-9a-f-]{36}\?paso=[0-9a-f-]{36}$/);
  // El link de acción abre "Vincular" en la pestaña de la obra, sin salir del paso;
  // al cerrarlo, queda el paso abierto.
  await expect(paso.getByRole("link", { name: "Vincular arquitecto ↗" })).toHaveAttribute(
    "href",
    /\/tareas\/[0-9a-f-]{36}\?paso=[0-9a-f-]{36}&vincular=arquitecto$/
  );
  await paso.getByRole("link", { name: "Vincular arquitecto ↗" }).click();
  await expect(page.getByRole("dialog")).toHaveCount(2);
  await expect(panel(page)).toContainText("Vincular contacto");
  await panel(page).getByRole("button", { name: "Cerrar" }).click();
  await expect(page.getByRole("dialog")).toHaveCount(1);
  await expect(page).toHaveURL(/\/tareas\/[0-9a-f-]{36}\?paso=[0-9a-f-]{36}$/);
  await expect(paso.getByRole("tab", { name: obra })).toBeVisible();
  await paso.getByRole("button", { name: "Cerrar" }).click();
  await expect(paso).toBeHidden();

  await expect(page.getByText("Sobre:")).toBeVisible();
  await page.getByRole("link", { name: `${obra} ↗` }).click();
  await expect(page).toHaveURL(/\/obras\/[0-9a-f-]{36}$/);

  await expect(page.getByText("Hilos", { exact: true })).toBeVisible();
  const hilo = page.getByRole("link", { name: new RegExp(plantilla) });
  await expect(hilo).toContainText("0/1 completados");
  await hilo.click();
  await expect(page).toHaveURL(/\/tareas\/[0-9a-f-]{36}$/);
  await ctx.close();
});

// Hallazgo 8: un paso de plantilla asignado a un equipo. "Equipo Zqx pruebas"
// lo arma `obras.spec.ts`, con Tester 2 de delegador; Juan es independiente,
// así que el paso llega como pedido a la bandeja del equipo.
test("Juan pide un paso de plantilla a un equipo y le llega a su jefe", async ({ browser }) => {
  const alEquipo = `Pedido al equipo ${marca}`;
  const { ctx, page } = await como(browser, "tester");
  await page.goto("/tareas/plantillas");
  await page.getByRole("button", { name: "Nueva plantilla" }).click();
  const form = panel(page);
  await form.getByLabel("Nombre").fill(alEquipo);
  await form.getByLabel("Título", { exact: true }).fill(`Medir ${marca}`);
  await form.getByLabel("Asignado").selectOption({ label: "Equipo Zqx pruebas · pedido" });
  await form.getByRole("button", { name: "Crear plantilla" }).click();
  await expect(form).toBeHidden();

  const card = page.locator("div.card").filter({ hasText: alEquipo });
  await card.getByRole("button", { name: "Usar" }).click();
  const usar = panel(page);
  await expect(usar.getByText("Equipo Zqx pruebas", { exact: true })).toBeVisible();
  await usar.getByRole("button", { name: "Crear hilo" }).click();
  await expect(page).toHaveURL(/\/tareas\/[0-9a-f-]{36}$/);
  await expect(page.getByText(`Medir ${marca}`)).toBeVisible();
  await ctx.close();

  const jefe = await como(browser, "tester2");
  await jefe.page.goto("/tareas/equipo");
  await jefe.page.getByRole("button", { name: /^Pedidos/ }).click();
  await expect(jefe.page.getByText(`Medir ${marca}`)).toBeVisible();
  await jefe.ctx.close();
});
