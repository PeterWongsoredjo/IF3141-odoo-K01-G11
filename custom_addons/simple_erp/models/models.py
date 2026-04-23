from odoo import models, fields, api, tools

class RawProduct(models.Model):
    _name = 'simple_erp.raw_product'
    _description = 'Raw Product Stock Management'

    name = fields.Char(string='Product Name', required=True)
    stock_amount = fields.Float(string='Current Stock Amount', default=0.0)

class Product(models.Model):
    _name = 'simple_erp.product'
    _description = 'Finished Product Management'

    name = fields.Char(string='Product Name', required=True)
    stock_amount = fields.Float(string='Current Stock Amount', default=0.0)

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
                rec.product_id.stock_amount -= rec.quantity_sold
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
                rec.product_id.stock_amount += rec.quantity_purchased
        return records


class DashboardMetrics(models.Model):
    _name = 'simple_erp.dashboard_metrics'
    _description = 'ERP Dashboard Metrics'
    _auto = False

    date = fields.Date(string='Date', readonly=True)
    income_amount = fields.Float(string='Income Total', readonly=True)
    expense_amount = fields.Float(string='Expense Total', readonly=True)
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