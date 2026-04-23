from odoo import models, fields, api

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