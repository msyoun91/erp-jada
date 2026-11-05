import { Modulo } from "@/components/layout/Modulo";
import { puedeVerObras, puedeVerTodas } from "@/modules/obras/permissions";

export default async function ObrasLayout({ children }: { children: React.ReactNode }) {
  const [ver, verTodas] = await Promise.all([puedeVerObras(), puedeVerTodas()]);
  const tabs = [
    ...(ver ? [{ codigo: "obras_ver", label: "Obras", href: "/obras" }] : []),
    ...(verTodas ? [{ codigo: "obras_todas", label: "Todas", href: "/obras/todas" }] : []),
  ];

  return (
    <Modulo modulo="obras" tabs={tabs}>
      {children}
    </Modulo>
  );
}
