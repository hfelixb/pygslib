'''
PyGSLIB nonlinear, Module with function for nonlinear geostatistics  

Copyright (C) 2015 Adrian Martinez Vargas 

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
any later version.
   
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
   
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>
'''

'''
Code based on paper:

A Step by Step Guide to Bi-Gaussian Disjunctive Kriging, by 
Julian M. Ortiz, Bora Oz, Clayton V. Deutsch
Geostatistics Banff 2004
Volume 14 of the series Quantitative Geology and Geostatistics pp 1097-1102

see also:

http://www.ccgalberta.com/ccgresources/report05/2003-107-dk.pdf
http://www.ccgalberta.com/ccgresources/report04/2002-106-hermite.pdf
http://www.ccgalberta.com/ccgresources/report06/2004-112-inference_under_mg.pdf
Mining Geostatistics: A. G. Journel, Andre G. Journel, C. J
'''


cimport numpy as np
import numpy as np
from scipy.stats import norm
from scipy.optimize import brentq

# ----------------------------------------------------------------------
#   Functions for punctual gaussian anamorphosis 
# ----------------------------------------------------------------------

#the recurrent formula for normalized polynomials
cpdef recurrentH(np.ndarray [double, ndim=1] y, K=30):
    """ 
    recurrentH(y, K=30)
    
    Calculate the hermite polynomials with the recurrent formula
    
    Parameters
    ----------
    y : 1D array of floats
        Gaussian values calculated for the right part of the bin.
    K  : integer, default 30
        Number of hermite polynomials 

    Returns
    -------
    H : 2D array of floats
        Hermite monomials H(i,y) with shape [K+1,len(y)]
      
    See Also
    --------
    pygslib.__dist_transf.anatbl
       
    Notes
    -----  
    The y values may be calculated on the right side of the bin, 
    as shown in fig VI.13, page 478 of Mining Geostatistics: 
    A. G. Journel, Andre G. Journel, C. J. The function 
    pygslib.__dist_transf.anatbl was prepared to provide these values,
    considering declustering weight if necessary. 
    
    The results from pygslib.__dist_transf.ns_ttable are inappropriate 
    for this calculation because are the mid interval in the bin.  
    """
    assert(K>=1)
    
    cdef np.ndarray [double, ndim=2] H
    cdef int k
    
    H=np.ones((K+1,len(y))) 
    #H[0,:]=1                #first monomial already ones 
    H[1,:]=-y               #second monomial
    
    # recurrent formula
    for k in range(1,K):
        H[k+1,:]= -1/np.sqrt(k+1)*y*H[k,:]-np.sqrt(k/float(k+1))*H[k-1,:]
    
    return H   #this is a 2D array of H (ki,yi)


#fit PCI for f(x)=Z(x)
cpdef fit_PCI(np.ndarray [double, ndim=1] z,
              np.ndarray [double, ndim=1] y,
              np.ndarray [double, ndim=2] H,
              float meanz=np.nan):
    """ 
    fit_PCI(z,y,H, meanz=np.nan)
    
    or 
    
    fit_PCI(z,y,H, meanz=float('NaN'))
    
    Fit the hermite coefficient (PCI) 
    
    Parameters
    ----------
    z  : 1D array of floats
        Raw values sorted
    y  : 1D array of floats
        Gaussian values calculated for the right part of the bin.
    K  : integer, default 30
        Number of hermite polynomials 
    meanz: float, default np.nan
        mean of z, if NaN then the mean will be calculated as np.mean(z)

    Returns
    -------
    PCI : 1D array of floats
        Hermite coefficients or PCI 
      
    See Also
    --------
    var_PCI
       
    Notes
    -----  
    PCI[0]=mean(z) and the sum=(PCI[1...n]^2). To validate the fit 
    calculate the variance with var_PCI funtion and compare it with the 
    experimental variance of z. You may also validate the fit by 
    calculating the error= z-PHI(y), where PHI(y) are the z' values
    calculated with the hermite polynomial expansion.  
    
    """
    
    assert y.shape[0]==z.shape[0]==H.shape[1], 'Error: wrong shape on input array'
    
    cdef np.ndarray [double, ndim=1] PCI
    
    # if no mean provided
    if np.isnan(meanz):
        meanz = np.mean(z)
    
    PCI=np.zeros(H.shape[0])
    PCI[0]=np.mean(z)
    
    for p in range(1,H.shape[0]):
        for i in range(1,H.shape[1]):
            PCI[p]+=(z[i-1]-z[i])*1/np.sqrt(p)*H[p-1,i]*norm.pdf(y[i])
    
    return PCI


#get variance from PCI
cpdef var_PCI(np.ndarray [double, ndim=1] PCI):
    """ 
    var_PCI(PCI)
     
    Calculates the variance from hermite coefficient (PCI) 
     
    Parameters
    ----------
    PCI : 1D array of floats
        hermite coefficient

    Returns
    -------
    var : float
        variance calculated with hermite polynomials
      
    See Also
    --------
    fit_PCI
       
    Notes
    -----  
    The output may be used for validation of the PCI coefficients, it 
    may be close to the experimental variance of z.
    
    """
    a=PCI[1:]**2
    return np.sum(a)

#expand anamorphosis
cpdef expand_anamor(np.ndarray [double, ndim=1] PCI, 
                    np.ndarray [double, ndim=2] H,
                    float r=1.):
    """ 
    expand_anamor(PCI,H,r=1)
    
    Expand the anamorphosis function, that is Z = SUMp(PSIp*r^p*Hp(Yv))
    
    r is the support effect. If r = 1 Z with point support will returned. 
    
    
    Parameters
    ----------
    PCI : 1D array of floats
        hermite coefficient
    H : 2D array of floats
        Hermite monomials H(i,y) with shape [K+1,len(y)]. See recurrentH
    r : float, default 1
        the support effect

    Returns
    -------
    PCI : 1D array of floats
        Hermite coefficients or PCI 
      
    See Also
    --------
    recurrentH
       
    Notes
    -----  
  
    """
    
    cdef np.ndarray [double, ndim=1] Z
    cdef int p
        
    Z=np.zeros(H.shape[1])
    for p in range(len(PCI)):
        Z+=PCI[p]*H[p,:]*r**p
    
    return Z

cpdef Y2Z(np.ndarray [double, ndim=1] Y,
        np.ndarray [double, ndim=1] PCI,
        float r=1):
    """ 
    Y2Z( Y, PCI, r=1)
    
    Gaussian (Y) to raw (Z) transformation 
    
    This is a convenience functions. It calls H=recurrentH(K,Y) and
    then returns Z = expand_anamor(PCI,H,r). K is deduced from 
    PCI.shape[0].
    
    
    Parameters
    ----------
    PCI : 1D array of floats
        hermite coefficient
    Y : 1D array of floats
        Gaussian values
    r : float, default 1
        the support effect

    Returns
    -------
    Z : 1D array of floats
        raw values corresponding to Y 
      
    See Also
    --------
    recurrentH, expand_anamor
       
    Notes
    -----  
  
    """
    
    cdef int K
    cdef np.ndarray [double, ndim=2] H
    
    K=PCI.shape[0]-1
    H=recurrentH(Y,K)
    
    #and the new Z values with the existing PCI
    return expand_anamor(PCI,H,r)

# Test from here

cpdef Z2Y_linear(np.ndarray [double, ndim=1] z,
                 np.ndarray [double, ndim=1] zm,
                 np.ndarray [double, ndim=1] ym,
                 float zmin,
                 float zmax):
    """ 
    Z2Y_linear(z,zm,ym,zmin=None,zmax=None)
     
    Raw (Z) to Gaussian (Y) transformation 
    
    Given a set of pairs [zm,ym] representing an experimental 
    gaussian anamorphosis, this functions linearly y values 
    corresponding to z within the [zmin, zmax] interval
    
    Parameters
    ----------
    PCI : 1D array of floats
        hermite coefficient
    Y : 1D array of floats
        Gaussian values
    r : float, default 1
        the support effect

    Returns
    -------
    Z : 1D array of floats
        raw values corresponding to Y 
      
    See Also
    --------
    Y2Z
       
    Notes
    -----  
  
    """    
    
    #assert this if not created internally... (zm has to be an increasing sequence)
    assert np.all(np.diff(zm) >= 0), 'zm has to be an increasing sequence'
    
    return np.interp(z, zm, ym, left=zmin, right=zmax)

# ----------------------------------------------------------------------
#   Extra Functions for support and information effect  
# ----------------------------------------------------------------------


cpdef f_var_Zv(float r,
               np.ndarray [double, ndim=1] PCI,
               float Var_Zv=0):
    """
    f_var_Zv(r,PCI,Var_Zv=0)
    
    This is an internal function used to deduce the coefficients r
    (or s), representing the support effect. It defines the relations:  
    
    
        Var(Zv) = sum PCI^2 * r^(n*2) 
        
        or 
    
        Var(Zv*) = sum PCI^2 * s^(n*2)
    
    r is necessary to account for information effect
    s is necessary to account for smoothing in the information effect.        
        
    see "The information effect and estimating recoverable reserves"
    J. Deraisme (Geovariances), C. Roth (Geovariances) for more information
    
    Parameters
    ----------
    r : float
        r or s coefficient representing support effect of Zv (or Zv*)
    PCI : 1D array of floats
        hermite coefficients
    Var_Zv : float
        Block Variance var(Zv) or var(Zv*) 
    
    Notes
    -----
    var(Zv) can be calculated as C(0)-gamma(v,v) or C(v,v) see function 
    block_covariance 
    
    var(Zv*) = var(Zv) - Kriging variance - 2*LaGrange multiplier
     
    In case of information effect this can be calculated with a dummy 
    dataset in a single block representing future information, for 
    example blast holes. 
    
    
    """
    
    cdef float a 
    cdef int i
    
    a=0.
    
    for i in range(1,len(PCI)):
       a+=PCI[i]**2. * r**(2.*i)
    return a-Var_Zv

# this is to pass a function to brentq
# auxiliar function covar (Zv,Zv*) = sum PCI^2 * r^n * s^n * ro^n 
# see "The information effect and estimating recoverable reserves"
# J. Deraisme (Geovariances), C. Roth (Geovariances)
cpdef f_covar_ZvZv(float ro,
                   float s,
                   float r,
                   np.ndarray [double, ndim=1] PCI,
                   float Covar_ZvZv=0):
    """
    f_covar_ZvZv(ro,s,r,PCI,Covar_ZvZv=0)
    
    This is an internal function used to deduce the coefficients 
    ro = covar(Yv, Yv*). This function represents the expression:  
    
    
        Covar (Zv,Zv*) = sum PCI^2 * r^n * s^n * ro^n
        
    ro is necessary to account for the conditional bias in the 
    information effect.     
        
    see "The information effect and estimating recoverable reserves"
    J. Deraisme (Geovariances), C. Roth (Geovariances) for more information
    
    Parameters
    ----------
    r, ro, s : float
        support effect and information effect coefficients.
    PCI : 1D array of floats
        hermite coefficients
    Covar_ZvZv : float
        Block covariance (correlation) between true Zv and estimate Zv* 
    
    Notes
    -----
    Covar (Zv,Zv*) = var(Zv) - Kriging variance - LaGrange multiplier
    
    see expression 7.47, page 97 on Basic Linear Geostatistics by 
    Margaret Armstrong.
    
    In case of information effect this can be calculated with a dummy 
    dataset in a single block representing future information, for 
    example blast holes. 
    
    Note that the slop of regression is  
    
    p = Covar (Zv,Zv*) / (Covar (Zv,Zv*)  - LaGrange multiplier)
    
    """
    
    cdef float a 
    cdef int i
    
    a=0.
    
    for i in range(1,len(PCI)):
       a+=PCI[i]**2. * r**i * s**i * ro**i
    return a-Covar_ZvZv


#calculate support effect coefficient r
cpdef get_r(float Var_Zv,
            np.ndarray [double, ndim=1] PCI):
    """ 
    get_r(Var_Zv,PCI)
     
    This function deduces the value of the support effect coefficient r
    or the informattion effect coefficient, smoothing component, s 
    defined by the equations: 
    
    
        Var(Zv) = sum PCI^2 * r^(n*2) 
        
        and 
    
        Var(Zv*) = sum PCI^2 * s^(n*2)
    
    The value of r is deduced by finding the root of the equation 
    f_var_Zv, using the classic Brent method (see scipy.optimize.brentq) 
    
    
    Parameters
    ----------
    PCI : 1D array of floats
        hermite coefficient
    Var_Zv : float
        Block variance

    Returns
    -------
    r :  float
        support effect coefficient r or information effect coefficient s
      
    See Also
    --------
    f_var_Zv, fit_PCI, scipy.optimize.brentq
    
    Notes
    -----
    var(Zv) can be calculated as C(0)-gamma(v,v) or C(v,v) see function 
    block_covariance 
    
    var(Zv*) = var(Zv) - Kriging variance - 2*LaGrange multiplier
     
    In case of information effect this can be calculated with a dummy 
    dataset in a single block representing future information, for 
    example blast holes. 
    
    """
    
    return brentq(f=f_var_Zv, a=0, b=1, args=(PCI,Var_Zv))

#calculate information effect coefficient ro
def get_ro(float Covar_ZvZv,
           np.ndarray [double, ndim=1] PCI,
           float r,
           float s):
    """
    get_ro(Covar_ZvZv,PCI,r,s)
    
    This function deduces the information effect coefficient, 
    conditional bias component, ro defined by the equations: 
    
        Covar (Zv,Zv*) = sum PCI^2 * r^n * s^n * ro^n
        
    ro is necessary to account for the conditional bias in the 
    information effect.     
        
    The value of ro is deduced by finding the root of the equation 
    f_covar_ZvZv, using the classic Brent method (see 
    scipy.optimize.brentq)
    
    Parameters
    ----------
    r, s : float
        support effect and information effect (smoothing component)
    PCI : 1D array of floats
        hermite coefficients
    Covar_ZvZv : float
        Block covariance (correlation) between true Zv and estimate Zv* 
    
    Notes
    -----
    Covar (Zv,Zv*) = var(Zv) - Kriging variance - LaGrange multiplier
    
    see expression 7.47, page 97 on Basic Linear Geostatistics by 
    Margaret Armstrong.
    
    In case of information effect this can be calculated with a dummy 
    dataset in a single block representing future information, for 
    example blast holes. 
    
    Note that the slop of regression is  
    
    p = Covar (Zv,Zv*) / (Covar (Zv,Zv*)  - LaGrange multiplier)
    
    """
    
    return brentq(f=f_covar_ZvZv, a=0, b=1, args=(s,r,PCI,Covar_ZvZv))


