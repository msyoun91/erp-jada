import { notFound } from "next/navigation";
import { puedeCrearEmpresa, puedeVerEmpresas } from "@/modules/obras/permissions";
import { getEmpresas } from "@/modules/obras/queries";
import { EmpresasView } from "@/modules/obras/components/EmpresasView";

export default async function EmpresasPage() {
  if (!(await puedeVerEmpresas())) notFound();

  const [empresas, crear] = await Promise.all([getEmpresas(), puedeCrearEmpresa()]);

  return <EmpresasView empresas={empresas} puedeCrear={crear} />;
}
