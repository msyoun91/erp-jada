import { getDashboardData, getWidgetPrefs } from "@/modules/dashboard/queries";
import { getWidgetsPermitidos } from "@/modules/dashboard/permissions";
import { DashboardView } from "@/modules/dashboard/components/DashboardView";

export default async function DashboardPage() {
  const [data, prefs, widgets] = await Promise.all([
    getDashboardData(),
    getWidgetPrefs(),
    getWidgetsPermitidos(),
  ]);

  return <DashboardView data={data} widgets={widgets} prefs={prefs} />;
}
