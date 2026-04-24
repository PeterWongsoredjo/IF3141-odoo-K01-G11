from odoo import models, fields, api, tools


class StockChangeLog(models.Model):
    _name = 'simple_erp.stock_change_log'
    _description = 'Stock Change History'
    _order = 'changed_at asc, id asc'

    changed_at = fields.Datetime(string='Changed At', default=fields.Datetime.now, required=True, readonly=True)
    source = fields.Selection([
        ('manual_raw', 'Manual Raw Stock Update'),
        ('manual_product', 'Manual Finished Product Update'),
        ('sale', 'Sale'),
        ('invoice', 'Invoice / Restock'),
    ], string='Source', required=True)
    reference = fields.Char(string='Reference')
    raw_product_id = fields.Many2one('simple_erp.raw_product', string='Raw Product')
    product_id = fields.Many2one('simple_erp.product', string='Finished Product')
    change_amount = fields.Float(string='Net Change', readonly=True)
    stock_in_amount = fields.Float(string='Stock In', readonly=True)
    stock_out_amount = fields.Float(string='Stock Out', readonly=True)
    resulting_stock = fields.Float(string='Resulting Stock', readonly=True)


class RawProduct(models.Model):
    _name = 'simple_erp.raw_product'
    _description = 'Raw Product Stock Management'

    name = fields.Char(string='Product Name', required=True)
    stock_amount = fields.Float(string='Current Stock Amount', default=0.0)

    def write(self, vals):
        if self.env.context.get('skip_stock_log') or 'stock_amount' not in vals:
            return super(RawProduct, self).write(vals)

        old_stock = {rec.id: rec.stock_amount for rec in self}
        result = super(RawProduct, self).write(vals)

        log_vals = []
        for rec in self:
            previous = old_stock.get(rec.id, 0.0)
            delta = rec.stock_amount - previous
            if tools.float_is_zero(delta, precision_digits=6):
                continue

            log_vals.append({
                'source': 'manual_raw',
                'reference': rec.name,
                'raw_product_id': rec.id,
                'change_amount': delta,
                'stock_in_amount': delta if delta > 0 else 0.0,
                'stock_out_amount': -delta if delta < 0 else 0.0,
                'resulting_stock': rec.stock_amount,
            })

        if log_vals:
            self.env['simple_erp.stock_change_log'].sudo().create(log_vals)

        return result

class Product(models.Model):
    _name = 'simple_erp.product'
    _description = 'Finished Product Management'

    name = fields.Char(string='Product Name', required=True)
    stock_amount = fields.Float(string='Current Stock Amount', default=0.0)

    def write(self, vals):
        if self.env.context.get('skip_stock_log') or 'stock_amount' not in vals:
            return super(Product, self).write(vals)

        old_stock = {rec.id: rec.stock_amount for rec in self}
        result = super(Product, self).write(vals)

        log_vals = []
        for rec in self:
            previous = old_stock.get(rec.id, 0.0)
            delta = rec.stock_amount - previous
            if tools.float_is_zero(delta, precision_digits=6):
                continue

            log_vals.append({
                'source': 'manual_product',
                'reference': rec.name,
                'product_id': rec.id,
                'change_amount': delta,
                'stock_in_amount': delta if delta > 0 else 0.0,
                'stock_out_amount': -delta if delta < 0 else 0.0,
                'resulting_stock': rec.stock_amount,
            })

        if log_vals:
            self.env['simple_erp.stock_change_log'].sudo().create(log_vals)

        return result

class SalesRecord(models.Model):
    _name = 'simple_erp.sales_record'
    _description = 'Product Sales Record'

    name = fields.Char(string='Sale Description / CSV Ref', required=True)
    date = fields.Date(string='Date', default=fields.Date.context_today)
    product_id = fields.Many2one('simple_erp.product', string='Sold Product')
    quantity_sold = fields.Float(string='Quantity Sold')
    income_amount = fields.Float(string='Total Income')

    @api.model_create_multi
    def create(self, vals_list):
        records = super(SalesRecord, self).create(vals_list)
        for rec in records:
            if rec.product_id:
                # Deduct stock when a sale happens
                new_stock = rec.product_id.stock_amount - rec.quantity_sold
                rec.product_id.with_context(skip_stock_log=True).write({'stock_amount': new_stock})
                self.env['simple_erp.stock_change_log'].sudo().create({
                    'source': 'sale',
                    'reference': rec.name,
                    'product_id': rec.product_id.id,
                    'change_amount': -rec.quantity_sold,
                    'stock_in_amount': 0.0,
                    'stock_out_amount': rec.quantity_sold,
                    'resulting_stock': rec.product_id.stock_amount,
                })
        return records

class InvoiceRecord(models.Model):
    _name = 'simple_erp.invoice_record'
    _description = 'Vendor Invoice / Restock Record'

    name = fields.Char(string='Invoice / Receipt Number', required=True)
    date = fields.Date(string='Date', default=fields.Date.context_today)
    product_id = fields.Many2one('simple_erp.raw_product', string='Restocked Product')
    quantity_purchased = fields.Float(string='Quantity Bought')
    expense_amount = fields.Float(string='Total Expense')
    receipt_image = fields.Binary(string='Invoice Image', attachment=True)

    @api.model_create_multi
    def create(self, vals_list):
        records = super(InvoiceRecord, self).create(vals_list)
        for rec in records:
            if rec.product_id:
                # Add back to stock when purchased/invoiced
                new_stock = rec.product_id.stock_amount + rec.quantity_purchased
                rec.product_id.with_context(skip_stock_log=True).write({'stock_amount': new_stock})
                self.env['simple_erp.stock_change_log'].sudo().create({
                    'source': 'invoice',
                    'reference': rec.name,
                    'raw_product_id': rec.product_id.id,
                    'change_amount': rec.quantity_purchased,
                    'stock_in_amount': rec.quantity_purchased,
                    'stock_out_amount': 0.0,
                    'resulting_stock': rec.product_id.stock_amount,
                })
        return records


class DashboardMetrics(models.Model):
    _name = 'simple_erp.dashboard_metrics'
    _description = 'ERP Dashboard Metrics'
    _auto = False

    date = fields.Date(string='Date', readonly=True)
    income_amount = fields.Float(string='Income Total', readonly=True)
    expense_amount = fields.Float(string='Expense Total', readonly=True)
    net_total_amount = fields.Float(string='Net Total', readonly=True)
    stock_in_amount = fields.Float(string='Stock In Total', readonly=True)
    stock_out_amount = fields.Float(string='Stock Out Total', readonly=True)

    def init(self):
        tools.drop_view_if_exists(self.env.cr, self._table)
        self.env.cr.execute("""
            CREATE OR REPLACE VIEW simple_erp_dashboard_metrics AS (
                SELECT
                    row_number() OVER (ORDER BY t.date) AS id,
                    t.date,
                    SUM(t.income_amount) AS income_amount,
                    SUM(t.expense_amount) AS expense_amount,
                    SUM(t.income_amount) - SUM(t.expense_amount) AS net_total_amount,
                    SUM(t.stock_in_amount) AS stock_in_amount,
                    SUM(t.stock_out_amount) AS stock_out_amount
                FROM (
                    SELECT
                        sr.date::date AS date,
                        SUM(sr.income_amount) AS income_amount,
                        0::float AS expense_amount,
                        0::float AS stock_in_amount,
                        SUM(sr.quantity_sold) AS stock_out_amount
                    FROM simple_erp_sales_record sr
                    GROUP BY sr.date

                    UNION ALL

                    SELECT
                        ir.date::date AS date,
                        0::float AS income_amount,
                        SUM(ir.expense_amount) AS expense_amount,
                        SUM(ir.quantity_purchased) AS stock_in_amount,
                        0::float AS stock_out_amount
                    FROM simple_erp_invoice_record ir
                    GROUP BY ir.date
                ) t
                GROUP BY t.date
            )
        """)


class DashboardFinanceLine(models.Model):
    _name = 'simple_erp.dashboard_finance_line'
    _description = 'ERP Finance Dashboard Line Series'
    _auto = False

    date = fields.Date(string='Date', readonly=True)
    metric = fields.Selection([
        ('income', 'Income'),
        ('expense', 'Expense'),
        ('net', 'Net Total'),
    ], string='Metric', readonly=True)
    amount = fields.Float(string='Amount', readonly=True)

    def init(self):
        tools.drop_view_if_exists(self.env.cr, self._table)
        self.env.cr.execute("""
            CREATE OR REPLACE VIEW simple_erp_dashboard_finance_line AS (
                WITH finance AS (
                    SELECT
                        t.date,
                        SUM(t.income_amount) AS income_amount,
                        SUM(t.expense_amount) AS expense_amount
                    FROM (
                        SELECT
                            sr.date::date AS date,
                            SUM(sr.income_amount) AS income_amount,
                            0::float AS expense_amount
                        FROM simple_erp_sales_record sr
                        GROUP BY sr.date

                        UNION ALL

                        SELECT
                            ir.date::date AS date,
                            0::float AS income_amount,
                            SUM(ir.expense_amount) AS expense_amount
                        FROM simple_erp_invoice_record ir
                        GROUP BY ir.date
                    ) t
                    GROUP BY t.date
                )
                SELECT
                    row_number() OVER (ORDER BY f.date, s.metric) AS id,
                    f.date,
                    s.metric,
                    CASE
                        WHEN s.metric = 'income' THEN f.income_amount
                        WHEN s.metric = 'expense' THEN f.expense_amount
                        ELSE f.income_amount - f.expense_amount
                    END AS amount
                FROM finance f
                CROSS JOIN (
                    SELECT 'income'::varchar AS metric
                    UNION ALL SELECT 'expense'::varchar
                    UNION ALL SELECT 'net'::varchar
                ) s
            )
        """)