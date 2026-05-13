/** @odoo-module **/
import { Component, onMounted, onPatched, onWillStart, onWillUnmount, useRef, useState } from "@odoo/owl";
import { registry } from "@web/core/registry";
import { useService } from "@web/core/utils/hooks";
import { loadBundle } from "@web/core/assets";

const PALETTE = {
    blue:         "#002b50",
    blueAlpha:    "rgba(0, 43, 80, 0.75)",
    blueLight:    "rgba(0, 43, 80, 0.12)",
    accent:       "#1e6fbd",
    success:      "#10b981",
    successAlpha: "rgba(16, 185, 129, 0.15)",
    danger:       "#ef4444",
    dangerAlpha:  "rgba(239, 68, 68, 0.15)",
    amber:        "#f59e0b",
    grid:         "rgba(0, 43, 80, 0.06)",
    text:         "#334155",
};

const BASE_SCALE = {
    x: { grid: { color: PALETTE.grid }, ticks: { color: PALETTE.text, font: { size: 11 } } },
    y: { grid: { color: PALETTE.grid }, ticks: { color: PALETTE.text, font: { size: 11 } } },
};

const BASE_LEGEND = {
    labels: { color: PALETTE.text, font: { family: "'Inter','Segoe UI',sans-serif", size: 12 }, padding: 16 },
};

const BASE_TOOLTIP = {
    backgroundColor: "rgba(0,0,0,0.82)",
    titleFont: { size: 13, weight: "bold" },
    bodyFont: { size: 12 },
    padding: 12,
    cornerRadius: 8,
};

function toISODate(d) {
    return d.toISOString().split("T")[0];
}

export class DashboardCustom extends Component {
    static template = "simple_erp.DashboardCustom";

    setup() {
        this.orm = useService("orm");
        this.state = useState({
            data: null,
            loaded: false,
            filtering: false,
            dateFrom: "",
            dateTo: "",
            activePreset: "all",
            stockFilter: "all",
            salesPeriod: "month",
            expensePeriod: "month",
            financePeriod: "month",
        });

        this.rootRef    = useRef("root");
        this.salesRef   = useRef("salesChart");
        this.expenseRef = useRef("expenseChart");
        this.stockRef   = useRef("stockChart");
        this.financeRef = useRef("financeChart");

        this._charts = [];
        this._needsChartRender = false;

        onWillStart(async () => {
            await loadBundle("web.chartjs_lib");
            this.state.data = await this.orm.call(
                "simple_erp.dashboard_metrics",
                "get_combined_dashboard_data",
                []
            );
            this.state.loaded = true;
        });

        onMounted(() => {
            const root = this.rootRef.el;
            if (root) {
                const action = root.closest(".o_action");
                if (action) action.classList.add("erpd_active");

                // Size the dashboard to fill the viewport below its top offset,
                // and keep it correct on window resize.
                this._fitHeight();
                this._resizeHandler = () => this._fitHeight();
                window.addEventListener("resize", this._resizeHandler);
            }
            this._renderCharts();
        });

        onPatched(() => {
            if (this._needsChartRender) {
                this._needsChartRender = false;
                this._renderCharts();
            }
        });

        onWillUnmount(() => {
            if (this._resizeHandler) {
                window.removeEventListener("resize", this._resizeHandler);
                this._resizeHandler = null;
            }
            this._charts.forEach((c) => c.destroy());
            this._charts = [];
        });
    }

    _fitHeight() {
        const root = this.rootRef.el;
        if (!root || !root.isConnected) return;
        const top = root.getBoundingClientRect().top;
        root.style.height = `${Math.max(200, window.innerHeight - top)}px`;
    }

    // ── Formatters ────────────────────────────────────────────────────────────

    fmt(val) {
        const n = Number(val) || 0;
        return "Rp " + n.toLocaleString("id-ID", { maximumFractionDigits: 0 });
    }

    fmtNum(val) {
        const n = Number(val) || 0;
        return n.toLocaleString("id-ID", { maximumFractionDigits: 1 });
    }

    // ── Date filter ───────────────────────────────────────────────────────────

    applyPreset(preset) {
        const today = new Date();
        let dateFrom = "";
        let dateTo = toISODate(today);

        if (preset === "month") {
            dateFrom = toISODate(new Date(today.getFullYear(), today.getMonth(), 1));
        } else if (preset === "quarter") {
            const d = new Date(today);
            d.setMonth(d.getMonth() - 3);
            dateFrom = toISODate(d);
        } else if (preset === "year") {
            dateFrom = `${today.getFullYear()}-01-01`;
        } else {
            // "all" — clear both bounds
            dateTo = "";
        }

        this.state.dateFrom = dateFrom;
        this.state.dateTo = dateTo;
        this.state.activePreset = preset;
        this.applyFilter();
    }

    async applyFilter() {
        this.state.filtering = true;
        const data = await this.orm.call(
            "simple_erp.dashboard_metrics",
            "get_combined_dashboard_data",
            [],
            {
                date_from: this.state.dateFrom || false,
                date_to: this.state.dateTo || false,
                stock_filter: this.state.stockFilter !== "all" ? this.state.stockFilter : false,
                sales_period: this.state.salesPeriod,
                expense_period: this.state.expensePeriod,
                finance_period: this.state.financePeriod,
            }
        );
        // Preserve item list so the dropdown stays populated when filtering
        // returns no rows for the selected stock.
        if (this.state.data && this.state.data.stock_items && (!data.stock_items || !data.stock_items.length)) {
            data.stock_items = this.state.data.stock_items;
        }
        this.state.data = data;
        this.state.filtering = false;
        // Signal onPatched to re-render charts after OWL patches the DOM
        this._needsChartRender = true;
    }

    onStockFilterChange(ev) {
        this.state.stockFilter = ev.target.value;
        this.applyFilter();
    }

    onPeriodChange(chart, ev) {
        const key = chart + "Period";
        this.state[key] = ev.target.value;
        this.applyFilter();
    }

    // ── Chart rendering ───────────────────────────────────────────────────────

    _renderCharts() {
        const d = this.state.data;
        if (!d) return;

        this._charts.forEach((c) => c.destroy());
        this._charts = [];

        const Chart = window.Chart;
        if (!Chart) return;

        const make = (ref, config) => {
            if (ref.el) this._charts.push(new Chart(ref.el, config));
        };

        const PERIOD_LABEL = { day: "Daily", week: "Weekly", month: "Monthly", year: "Yearly" };

        // ── Chart 1: Sales Overview (Bar) ─────────────────────────────────
        make(this.salesRef, {
            type: "bar",
            data: {
                labels: d.sales.labels,
                datasets: [{
                    label: `${PERIOD_LABEL[this.state.salesPeriod]} Income (Rp)`,
                    data: d.sales.data,
                    backgroundColor: PALETTE.blueAlpha,
                    borderColor: PALETTE.blue,
                    borderWidth: 2,
                    borderRadius: 6,
                    borderSkipped: false,
                }],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false }, tooltip: BASE_TOOLTIP },
                scales: BASE_SCALE,
            },
        });

        // ── Chart 2: Expense Overview (Bar) ───────────────────────────────
        make(this.expenseRef, {
            type: "bar",
            data: {
                labels: d.expense.labels,
                datasets: [{
                    label: `${PERIOD_LABEL[this.state.expensePeriod]} Expenses (Rp)`,
                    data: d.expense.data,
                    backgroundColor: "rgba(239, 68, 68, 0.72)",
                    borderColor: PALETTE.danger,
                    borderWidth: 2,
                    borderRadius: 6,
                    borderSkipped: false,
                }],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false }, tooltip: BASE_TOOLTIP },
                scales: BASE_SCALE,
            },
        });

        // ── Chart 3: Stock Movement (Line) ────────────────────────────────
        make(this.stockRef, {
            type: "line",
            data: {
                labels: d.stock.labels,
                datasets: [
                    {
                        label: "Stock In",
                        data: d.stock.stock_in,
                        borderColor: PALETTE.success,
                        backgroundColor: PALETTE.successAlpha,
                        borderWidth: 2.5,
                        pointRadius: 3,
                        tension: 0.4,
                        fill: true,
                    },
                    {
                        label: "Stock Out",
                        data: d.stock.stock_out,
                        borderColor: PALETTE.danger,
                        backgroundColor: PALETTE.dangerAlpha,
                        borderWidth: 2.5,
                        pointRadius: 3,
                        tension: 0.4,
                        fill: true,
                    },
                ],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: BASE_LEGEND, tooltip: BASE_TOOLTIP },
                scales: BASE_SCALE,
            },
        });

        // ── Chart 4: Financial Performance (Multi-line) ───────────────────
        make(this.financeRef, {
            type: "line",
            data: {
                labels: d.finance.labels,
                datasets: [
                    {
                        label: "Income",
                        data: d.finance.income,
                        borderColor: PALETTE.accent,
                        backgroundColor: "rgba(30, 111, 189, 0.08)",
                        borderWidth: 2.5,
                        pointRadius: 4,
                        tension: 0.4,
                        fill: false,
                    },
                    {
                        label: "Expense",
                        data: d.finance.expense,
                        borderColor: PALETTE.danger,
                        backgroundColor: PALETTE.dangerAlpha,
                        borderWidth: 2.5,
                        pointRadius: 4,
                        tension: 0.4,
                        fill: false,
                    },
                    {
                        label: "Net Profit",
                        data: d.finance.net,
                        borderColor: PALETTE.success,
                        backgroundColor: PALETTE.successAlpha,
                        borderWidth: 2.5,
                        pointRadius: 4,
                        tension: 0.4,
                        fill: false,
                    },
                ],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: BASE_LEGEND, tooltip: BASE_TOOLTIP },
                scales: BASE_SCALE,
            },
        });
    }
}

registry.category("actions").add("simple_erp.dashboard_custom", DashboardCustom);
