import { DIAS_OPCIONES } from "@/components/ui/FiltroDias";
import { getDashboardData, getWidgetPrefs } from "@/modules/dashboard/queries";
import { getWidgetsPermitidos } from "@/modules/dashboard/permissions";
import { DashboardView } from "@/modules/dashboard/components/DashboardView";
import { getNumeros } from "@/modules/obras/queries";
import { WidgetObras } from "@/modules/obras/components/WidgetObras";

// `?dias=`: el período del widget Obras.
export default async function DashboardPage(props: PageProps<"/">) {
  const { dias: diasParam } = await props.searchParams;
  const dias = DIAS_OPCIONES.includes(Number(diasParam)) ? Number(diasParam) : 30;

  const [data, prefs, widgets] = await Promise.all([
    getDashboardData(),
    getWidgetPrefs(),
    getWidgetsPermitidos(),
  ]);

  const obras = widgets.find((w) => w.id === "obras" && (prefs[w.id] ?? true));
  const numeros = obras ? await getNumeros(dias) : [];

  return (
    <DashboardView
      data={data}
      widgets={widgets}
      prefs={prefs}
      modulos={{ obras: obras && <WidgetObras numeros={numeros} dias={dias} columnas={obras.columnas} /> }}
    />
  );
}
