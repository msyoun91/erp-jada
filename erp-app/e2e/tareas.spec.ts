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
  await expect(page.getByText("Vincular arquitecto").first()).toBeVisible();
  await expect(page.getByText("Coordinar con el arquitecto")).toHaveCount(0);
  await ctx.close();
});
