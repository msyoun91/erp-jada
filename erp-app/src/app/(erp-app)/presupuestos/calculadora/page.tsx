import { notFound } from "next/navigation";
import { Volver } from "@/components/ui/Volver";
import { getMonedaPrincipal } from "@/modules/catalogo/queries";
import { puedeCrear } from "@/modules/obras/permissions";
import { puedeArmar } from "@/modules/presupuestos/permissions";
import { getObrasParaPresupuestar, getPaquetesVenta } from "@/modules/presupuestos/queries";
import { Calculadora } from "./Calculadora";

export default async function CalculadoraPage() {
  if (!(await puedeArmar())) notFound();
  const [paquetes, obras, moneda, creaObras] = await Promise.all([
    getPaquetesVenta(),
    getObrasParaPresupuestar(),
    getMonedaPrincipal(),
    puedeCrear(),
  ]);
  return (
    <div className="flex flex-col gap-4">
      <Volver href="/presupuestos">Presupuestos</Volver>
      <div>
        <h2 className="t-h2">Calculadora</h2>
        <p className="t-caption">El precio de hoy de una ventana, sin IVA. No guarda nada hasta llevarla a un presupuesto.</p>
      </div>
      <Calculadora paquetes={paquetes} obras={obras} monedaPrincipal={moneda} creaObras={creaObras} />
    </div>
  );
}
