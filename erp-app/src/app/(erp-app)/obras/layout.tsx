import { Building2 } from "lucide-react";
import { Breadcrumb } from "@/components/layout/Breadcrumb";
import { ModuleTabs } from "@/components/layout/ModuleTabs";
import { BuscadorGlobal } from "@/modules/obras/components/BuscadorGlobal";
import {
  puedeVerAuditoria,
  puedeVerEmpresas,
  puedeVerObras,
  puedeVerPendientes,
  puedeVerPersonas,
} from "@/modules/obras/permissions";

export default async function ObrasLayout({ children }: { children: React.ReactNode }) {
  const [obras, empresas, personas, pendientes, auditoria] = await Promise.all([
    puedeVerObras(),
    puedeVerEmpresas(),
    puedeVerPersonas(),
    puedeVerPendientes(),
    puedeVerAuditoria(),
  ]);

  const tabs = [
    obras && { codigo: "obras_ver", label: "Obras", href: "/obras" },
    empresas && { codigo: "obras_empresas", label: "Empresas", href: "/obras/empresas" },
    personas && { codigo: "obras_personas", label: "Personas", href: "/obras/personas" },
    pendientes && { codigo: "obras_pendientes", label: "Pendientes", href: "/obras/pendientes" },
    auditoria && { codigo: "obras_auditoria", label: "Auditoría", href: "/obras/auditoria" },
  ].filter((t): t is { codigo: string; label: string; href: string } => Boolean(t));

  return (
    <div className="flex h-full flex-col">
      <Breadcrumb modulo="obras" tabs={tabs} />
      {/* El buscador va en la línea del título y no adentro de una tab: busca
          en las tres entidades, así que su efecto llega más lejos que la tab
          abierta. En mobile la barra se lleva su propio renglón. */}
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <h1 className="t-h1 flex items-center gap-2.5">
          <Building2 size={28} strokeWidth={1.75} className="text-brand-500 shrink-0" />
          Agenda de Obras
        </h1>
        {(obras || empresas || personas) && <BuscadorGlobal />}
      </div>
      <ModuleTabs modulo="obras" tabs={tabs} />
      {children}
    </div>
  );
}
