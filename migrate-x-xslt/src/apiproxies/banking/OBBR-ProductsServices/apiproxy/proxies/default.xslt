<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
  <xsl:template match="@*|node()" name="identity">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>
  <xsl:template match="VirtualHost"/>
  <xsl:template match="BasePath/text()[. = '/open-banking/products-services/v1']">
    <xsl:variable name="obbrProductsServicesBasePath">/open-banking-br/products-services/v1</xsl:variable>
    <xsl:value-of select="$obbrProductsServicesBasePath"/>
  </xsl:template>
</xsl:stylesheet>
