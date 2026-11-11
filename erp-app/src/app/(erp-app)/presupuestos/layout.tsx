import { Modulo } from "@/components/layout/Modulo";
import { puedeConfigurar, puedeRevisar, puedeVerPresupuestos } from "@/modules/presupuestos/permissions";

export default async function PresupuestosLayout({ children }: { children: React.ReactNode }) {
  const [ver, revisar, configurar] = await Promise.all([puedeVerPresupuestos(), puedeRevisar(), puedeConfigurar()]);
  const tabs = [
    ...(ver ? [{ codigo: "presupuestos_ver", label: "Presupuestos", href: "/presupuestos" }] : []),
    ...(revisar ? [{ codigo: "presupuestos_revision", label: "Revisión técnica", href: "/presupuestos/revision" }] : []),
    ...(configurar ? [{ codigo: "presupuestos_configuracion", label: "Configuración", href: "/presupuestos/configuracion" }] : []),
  ];

  return (
    <Modulo modulo="presupuestos" tabs={tabs}>
      {children}
    </Modulo>
  );
}
