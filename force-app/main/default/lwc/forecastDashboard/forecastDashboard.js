import { LightningElement, wire, track } from 'lwc';
import getMonthly from '@salesforce/apex/ForecastController.getMonthly';

export default class ForecastDashboard extends LightningElement {
    @track historyMonths = 12;
    @track horizonMonths = 6;

    @track series; // ForecastService.ForecastSeries
    @track tableRows = [];
    chartEl;
    chart; // HTMLCanvas 2D draw (no external libs)

    columns = [
        { label: 'Month', fieldName: 'month', type: 'text' },
        { label: 'Product Family', fieldName: 'productFamily', type: 'text' },
        { label: 'Actual', fieldName: 'actual', type: 'currency', cellAttributes: { alignment: 'right' } },
        { label: 'Pipeline (Weighted)', fieldName: 'pipeline', type: 'currency', cellAttributes: { alignment: 'right' } },
        { label: 'Predicted', fieldName: 'predicted', type: 'currency', cellAttributes: { alignment: 'right' } }
    ];

    @wire(getMonthly, { historyMonths: '$historyMonths', horizonMonths: '$horizonMonths' })
    wiredSeries({ data, error }) {
        if (data) {
            this.series = data;
            this.buildTable();
            this.renderChart();
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('Forecast wire error', error);
            this.series = undefined;
            this.tableRows = [];
            this.clearChart();
        }
    }

    onHistoryChange(event) {
        const v = parseInt(event.target.value, 10);
        if (!Number.isNaN(v) && v > 0) this.historyMonths = v;
    }
    onHorizonChange(event) {
        const v = parseInt(event.target.value, 10);
        if (!Number.isNaN(v) && v > 0) this.horizonMonths = v;
    }
    refresh() {
        // Re-invoke wire by spinning tracked params
        this.historyMonths = Number(this.historyMonths);
        this.horizonMonths = Number(this.horizonMonths);
    }

    monthKey(d) {
        // d is ISO string from Apex serialization; ensure Date object
        const dt = new Date(d);
        return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}`;
    }

    buildTable() {
        if (!this.series || !this.series.buckets) {
            this.tableRows = [];
            return;
        }
        const rows = this.series.buckets.map((b, idx) => ({
            key: `${idx}`,
            month: this.monthKey(b.monthStart),
            productFamily: b.productFamily,
            actual: b.actualAmount,
            pipeline: b.pipelineWeighted,
            predicted: b.predictedAmount
        }));
        this.tableRows = rows;
    }

    renderedCallback() {
        if (!this.chartEl) {
            this.chartEl = this.template.querySelector('canvas.chart');
            if (this.series) {
                this.renderChart();
            }
        }
    }

    clearChart() {
        if (this.chartEl) {
            const ctx = this.chartEl.getContext('2d');
            ctx.clearRect(0, 0, this.chartEl.width, this.chartEl.height);
        }
    }

    renderChart() {
        if (!this.chartEl || !this.series || !this.series.buckets) return;

        // Basic 2D canvas line chart: three series aggregated across families per month
        const width = this.chartEl.clientWidth || 900;
        const height = 320;
        this.chartEl.width = width;
        this.chartEl.height = height;

        const buckets = this.series.buckets;
        // Build ordered unique month keys
        const months = [];
        const monthIndex = new Map();
        for (const b of buckets) {
            const mk = this.monthKey(b.monthStart);
            if (!monthIndex.has(mk)) {
                monthIndex.set(mk, months.length);
                months.push(mk);
            }
        }
        const sums = months.map(() => ({ actual: 0, pipeline: 0, predicted: 0 }));
        for (const b of buckets) {
            const idx = monthIndex.get(this.monthKey(b.monthStart));
            sums[idx].actual += Number(b.actualAmount || 0);
            sums[idx].pipeline += Number(b.pipelineWeighted || 0);
            sums[idx].predicted += Number(b.predictedAmount || 0);
        }

        const maxY = Math.max(
            1,
            ...sums.map(s => Math.max(s.actual, s.pipeline, s.predicted))
        );

        const padL = 60;
        const padR = 20;
        const padT = 10;
        const padB = 40;
        const plotW = width - padL - padR;
        const plotH = height - padT - padB;

        const ctx = this.chartEl.getContext('2d');
        ctx.clearRect(0, 0, width, height);
        ctx.font = '12px sans-serif';
        ctx.fillStyle = '#54698d';

        // Axes
        ctx.strokeStyle = '#d8dde6';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(padL, padT);
        ctx.lineTo(padL, padT + plotH);
        ctx.lineTo(padL + plotW, padT + plotH);
        ctx.stroke();

        // Y ticks (4)
        ctx.fillStyle = '#54698d';
        ctx.textAlign = 'right';
        ctx.textBaseline = 'middle';
        for (let i = 0; i <= 4; i++) {
            const yv = (maxY * i) / 4;
            const y = padT + plotH - (plotH * i) / 4;
            ctx.fillText(this.formatCurrency(yv), padL - 6, y);
            ctx.strokeStyle = '#f3f2f2';
            ctx.beginPath();
            ctx.moveTo(padL, y);
            ctx.lineTo(padL + plotW, y);
            ctx.stroke();
        }

        // X labels (sparse if many months)
        ctx.textAlign = 'center';
        ctx.textBaseline = 'top';
        const step = Math.ceil(months.length / 12); // at most 12 labels
        for (let i = 0; i < months.length; i += step) {
            const x = padL + (plotW * i) / (months.length - 1 || 1);
            ctx.fillText(months[i], x, padT + plotH + 8);
        }

        // Line helper
        const drawLine = (color, accessor) => {
            ctx.strokeStyle = color;
            ctx.lineWidth = 2;
            ctx.beginPath();
            for (let i = 0; i < months.length; i++) {
                const x = padL + (plotW * i) / (months.length - 1 || 1);
                const val = accessor(sums[i]);
                const y = padT + plotH - (plotH * val) / maxY;
                if (i === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
            }
            ctx.stroke();
        };

        // Actual (blue), Pipeline (orange), Predicted (green)
        drawLine('#1b5297', s => s.actual);
        drawLine('#ff8f00', s => s.pipeline);
        drawLine('#2e844a', s => s.predicted);

        // Legend swatches are in HTML; nothing more here
    }

    formatCurrency(v) {
        try {
            return new Intl.NumberFormat(undefined, { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }).format(v || 0);
        } catch (e) {
            return `$${Math.round(v || 0).toLocaleString()}`;
        }
    }
}
