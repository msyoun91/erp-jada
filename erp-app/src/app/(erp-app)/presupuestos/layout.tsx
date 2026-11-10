import { Modulo } from "@/components/layout/Modulo";
import { puedeVerPresupuestos } from "@/modules/presupuestos/permissions";

export default async function PresupuestosLayout({ children }: { children: React.ReactNode }) {
  const tabs = (await puedeVerPresupuestos())
    ? [{ codigo: "presupuestos_ver", label: "Presupuestos", href: "/presupuestos" }]
    : [];

  return (
    <Modulo modulo="presupuestos" tabs={tabs}>
      {children}
    </Modulo>
  );
}
